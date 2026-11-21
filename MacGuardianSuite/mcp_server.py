#!/usr/bin/env python3
"""MacGuardian MCP server: lets Claude, Codex, Cursor or any MCP client run
MacGuardian's checkup, Tailscale doctor, browser audit and updates.

Zero dependencies (standard library only). Speaks MCP over stdio.

Register it with Claude Code:
    claude mcp add macguardian -- python3 /path/to/MacGuardianSuite/mcp_server.py

Long jobs (full checkup, software updates) run in the background: the tool
returns a job id right away, and get_job / get_checkup_report read the result.
Nothing here deletes files, removes apps or changes security settings.
"""
import json
import os
import signal
import subprocess
import sys
import time
import uuid

SUITE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.expanduser("~/.macguardian")
JOBS = os.path.join(DATA, "jobs")
CHECKUP_DIR = os.path.join(DATA, "checkup")
PROTOCOL = "2025-06-18"
VERSION = "1.0.0"

ENV = dict(os.environ)
ENV["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + ENV.get("PATH", "")
ENV["MG_NO_EMAIL"] = "1"
ENV["HOMEBREW_NO_AUTO_UPDATE"] = "1"


# ---------------------------------------------------------------- helpers

def run(cmd, timeout=600):
    """Run a suite command and return (exit_code, combined_output)."""
    try:
        p = subprocess.run(cmd, cwd=SUITE, env=ENV, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout, text=True)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired as e:
        return 124, (e.stdout or "") + f"\n[timed out after {timeout}s]"


def start_job(kind, cmd):
    os.makedirs(JOBS, mode=0o700, exist_ok=True)
    job_id = f"{kind}-{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:4]}"
    log = open(os.path.join(JOBS, job_id + ".log"), "w")
    p = subprocess.Popen(cmd, cwd=SUITE, env=ENV, stdin=subprocess.DEVNULL,
                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    with open(os.path.join(JOBS, job_id + ".json"), "w") as fh:
        json.dump({"id": job_id, "kind": kind, "pid": p.pid, "cmd": cmd,
                   "started": time.strftime("%Y-%m-%dT%H:%M:%S")}, fh)
    return job_id


def job_status(job_id):
    meta_path = os.path.join(JOBS, os.path.basename(job_id) + ".json")
    if not os.path.exists(meta_path):
        return None
    meta = json.load(open(meta_path))
    try:
        pid, status = os.waitpid(meta["pid"], os.WNOHANG)
        running = pid == 0
        if not running:
            meta["exit_code"] = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else status >> 8
            json.dump(meta, open(meta_path, "w"))
    except ChildProcessError:
        # Not our child (server restarted): fall back to a liveness check.
        try:
            os.kill(meta["pid"], 0)
            running = "exit_code" not in meta
        except OSError:
            running = False
    meta["running"] = running
    with open(os.path.join(JOBS, meta["id"] + ".log"), errors="replace") as fh:
        log = fh.read()
    meta["log_tail"] = "\n".join(log.splitlines()[-60:])
    return meta


def running_job(kind):
    if not os.path.isdir(JOBS):
        return None
    for name in sorted(os.listdir(JOBS), reverse=True):
        if name.startswith(kind + "-") and name.endswith(".json"):
            st = job_status(name[:-5])
            if st and st["running"]:
                return st
    return None


def latest_report():
    path = os.path.join(CHECKUP_DIR, "latest.json")
    if not os.path.exists(path):
        return None
    return json.load(open(path))


# ---------------------------------------------------------------- tools

def t_run_checkup(args):
    mode = args.get("mode", "standard")
    flags = {"quick": ["--quick"], "standard": [], "full": ["--full"]}.get(mode)
    if flags is None:
        return {"error": "mode must be quick, standard or full"}
    for step in args.get("skip", []) or []:
        flags += ["--skip", str(step)]
    if args.get("wait", mode == "quick"):
        code, out = run(["bash", "checkup.sh", "--json"] + flags, timeout=1800)
        try:
            return json.loads(out[out.index("{"):])
        except ValueError:
            return {"exit_code": code, "output": out[-4000:]}
    busy = running_job("checkup")
    if busy:
        return {"status": "already running", "job_id": busy["id"]}
    job = start_job("checkup", ["bash", "checkup.sh"] + flags)
    return {"status": "started", "job_id": job,
            "next": "Call get_job with this job_id (or get_checkup_report once it finishes). "
                    "Standard mode takes about 3-10 minutes, full mode up to 20."}


def t_get_checkup_report(_args):
    rep = latest_report()
    busy = running_job("checkup")
    if rep is None:
        return {"report": None, "running_job": busy and busy["id"],
                "hint": "No checkup has run yet. Call run_checkup."}
    return {"running_job": busy and busy["id"], "report": rep}


def t_tailscale_doctor(_args):
    code, out = run(["bash", "tailscale_doctor.sh", "--json"], timeout=60)
    try:
        return json.loads(out[out.index("{"):])
    except ValueError:
        return {"exit_code": code, "output": out}


def t_audit_browser_extensions(args):
    code, out = run([sys.executable, "-I", "browser_audit.py", "--json"], timeout=60)
    try:
        data = json.loads(out)
    except ValueError:
        return {"exit_code": code, "output": out}
    if not args.get("include_all"):
        data.pop("extensions", None)
    return data


def t_check_software_updates(_args):
    code, out = run(["bash", "package_updates.sh", "update"], timeout=600)
    return {"exit_code": code, "output": out[-8000:]}


def t_run_software_updates(args):
    busy = running_job("updates")
    if busy:
        return {"status": "already running", "job_id": busy["id"]}
    cmd = ["bash", "package_updates.sh", "upgrade", "--batch", "-y"]
    job = start_job("updates", cmd)
    return {"status": "started", "job_id": job,
            "note": "Homebrew downloads with /opt/homebrew/opt/curl/bin/curl; if LuLu or Little Snitch "
                    "is installed the user should allow it once. App Store upgrades need the user's "
                    "password ('sudo mas upgrade') and are listed, not installed."}


def t_self_check(_args):
    code, out = run(["bash", "self_check.sh"], timeout=120)
    return {"exit_code": code, "output": out}


def t_get_job(args):
    st = job_status(args.get("job_id", ""))
    if st is None:
        return {"error": "unknown job_id"}
    if not st["running"] and st["kind"] == "checkup":
        st["report"] = latest_report()
    return st


def t_cancel_job(args):
    st = job_status(args.get("job_id", ""))
    if st is None:
        return {"error": "unknown job_id"}
    if st["running"]:
        try:
            os.killpg(st["pid"], signal.SIGINT)
        except OSError as e:
            return {"error": str(e)}
        return {"status": "cancel requested", "job_id": st["id"]}
    return {"status": "not running", "job_id": st["id"]}


def t_open_app(_args):
    code, out = run(["open", "-a", "MacGuardian Suite"], timeout=20)
    return {"opened": code == 0, "output": out}


READ_ONLY = {"readOnlyHint": True, "destructiveHint": False}
TOOLS = {
    "run_checkup": (t_run_checkup, "Run MacGuardian's full checkup: Tailscale, security settings, MacGuardian self-check, "
                    "threat hunt, ClamAV malware scan, browser extensions and software updates. Read-only. "
                    "quick (~1-2 min, no malware/threat scan) waits for the result; standard/full run in the background "
                    "and return a job_id.", {
                        "mode": {"type": "string", "enum": ["quick", "standard", "full"], "default": "standard",
                                 "description": "quick skips malware+threat scans; full scans all of ~/Downloads"},
                        "skip": {"type": "array", "items": {"type": "string", "enum": [
                            "tailscale", "posture", "selfcheck", "threats", "malware", "browsers", "updates"]}},
                        "wait": {"type": "boolean", "description": "Block until done (default true only for quick)"},
                    }, READ_ONLY),
    "get_checkup_report": (t_get_checkup_report, "Return the most recent checkup report and whether one is running.", {}, READ_ONLY),
    "tailscale_doctor": (t_tailscale_doctor, "Diagnose Tailscale: logged out, stopped, duplicate Homebrew daemon fighting the app, "
                         "duplicate machines, relay-only connections. Returns problems and exact fix commands.", {}, READ_ONLY),
    "audit_browser_extensions": (t_audit_browser_extensions, "Audit Chrome, Brave, Edge, Arc and Firefox extensions and flag ones "
                                 "to remove (known-bad, impostors, free VPNs) or review, plus browser hijack policies.", {
                                     "include_all": {"type": "boolean", "description": "Also list every extension"}}, READ_ONLY),
    "check_software_updates": (t_check_software_updates, "Refresh Homebrew and list outdated tools, apps and App Store apps.", {},
                               {"readOnlyHint": True}),
    "run_software_updates": (t_run_software_updates, "Upgrade all Homebrew tools and apps in one batch (background job). "
                             "Ask the user before calling: it changes installed software.", {},
                             {"readOnlyHint": False, "destructiveHint": False, "openWorldHint": True}),
    "self_check": (t_self_check, "Verify MacGuardian itself has not been tampered with.", {}, READ_ONLY),
    "get_job": (t_get_job, "Status, exit code and last log lines of a background job (and the report when a checkup finishes).",
                {"job_id": {"type": "string"}}, READ_ONLY),
    "cancel_job": (t_cancel_job, "Stop a running background job.", {"job_id": {"type": "string"}}, {"destructiveHint": False}),
    "open_app": (t_open_app, "Open the MacGuardian Suite app.", {}, READ_ONLY),
}


# ---------------------------------------------------------------- protocol

def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(req):
    method, rid = req.get("method"), req.get("id")
    if method == "initialize":
        client_proto = (req.get("params") or {}).get("protocolVersion", PROTOCOL)
        return {"protocolVersion": client_proto if client_proto in ("2024-11-05", "2025-03-26", PROTOCOL) else PROTOCOL,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "macguardian", "version": VERSION},
                "instructions": "MacGuardian Watchdog security tools for this Mac. Start with run_checkup (mode quick "
                                "for a fast answer). Everything is read-only except run_software_updates; confirm with the "
                                "user before calling it, and never delete files on the user's behalf without asking."}
    if method == "ping":
        return {}
    if method == "tools/list":
        tools = []
        for name, (_fn, desc, props, ann) in TOOLS.items():
            tools.append({"name": name, "description": desc,
                          "inputSchema": {"type": "object", "properties": props, "additionalProperties": False},
                          "annotations": ann})
        return {"tools": tools}
    if method == "tools/call":
        params = req.get("params") or {}
        entry = TOOLS.get(params.get("name"))
        if not entry:
            raise ValueError(f"Unknown tool {params.get('name')}")
        try:
            result = entry[0](params.get("arguments") or {})
            is_error = isinstance(result, dict) and "error" in result
        except Exception as e:  # report tool failures to the model, not as protocol errors
            result, is_error = {"error": f"{type(e).__name__}: {e}"}, True
        return {"content": [{"type": "text", "text": json.dumps(result, indent=2)}],
                "structuredContent": result if isinstance(result, dict) else {"result": result},
                "isError": is_error}
    if rid is None:
        return None  # notification (e.g. notifications/initialized)
    raise LookupError(f"Method not found: {method}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
            continue
        rid = req.get("id")
        try:
            result = handle(req)
            if rid is not None:
                send({"jsonrpc": "2.0", "id": rid, "result": result})
        except LookupError as e:
            if rid is not None:
                send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": str(e)}})
        except Exception as e:
            if rid is not None:
                send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32602, "message": str(e)}})


if __name__ == "__main__":
    main()
