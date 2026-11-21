#!/usr/bin/env python3
"""Tests for the checkup helpers: browser_audit.py rules and the MCP server protocol.

Uses synthetic extension manifests in a temporary HOME; nothing reads the real
browser profiles.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SUITE = Path(__file__).resolve().parent.parent.parent / "MacGuardianSuite"
sys.path.insert(0, str(SUITE))


def make_chrome_ext(home, ext_id, manifest):
    d = Path(home) / "Library/Application Support/Google/Chrome/Default/Extensions" / ext_id / "1.0_0"
    d.mkdir(parents=True)
    (d / "manifest.json").write_text(json.dumps(manifest))


class TestBrowserAudit(unittest.TestCase):
    def run_audit(self, home):
        env = dict(os.environ, HOME=home)
        p = subprocess.run([sys.executable, "-I", str(SUITE / "browser_audit.py"), "--json"],
                           env=env, capture_output=True, text=True)
        return p.returncode, json.loads(p.stdout)

    def test_flags_impostor_known_bad_and_anonymous(self):
        with tempfile.TemporaryDirectory() as home:
            make_chrome_ext(home, "a" * 32, {"name": "HTTPS Everywhere", "version": "1.0",
                                            "host_permissions": ["<all_urls>"]})
            make_chrome_ext(home, "b" * 32, {"name": "Shady Helper", "version": "2",
                                            "permissions": ["cookies"], "host_permissions": ["*://*/*"]})
            make_chrome_ext(home, "c" * 32, {"name": "Free VPN Proxy", "version": "3"})
            make_chrome_ext(home, "d" * 32, {"name": "Nice Tool", "version": "4",
                                            "author": "Someone", "permissions": ["cookies"],
                                            "host_permissions": ["<all_urls>"]})
            code, rep = self.run_audit(home)
        verdicts = {e["name"]: e["verdict"] for e in rep["extensions"]}
        self.assertEqual(verdicts["HTTPS Everywhere"], "remove")   # impostor ID
        self.assertEqual(verdicts["Free VPN Proxy"], "remove")     # risky category
        self.assertEqual(verdicts["Shady Helper"], "review")       # cookies + all sites + anonymous
        self.assertEqual(verdicts["Nice Tool"], "ok")              # has an author
        self.assertEqual(code, 1)

    def test_clean_profile_exits_zero(self):
        with tempfile.TemporaryDirectory() as home:
            make_chrome_ext(home, "e" * 32, {"name": "Plain", "version": "1"})
            code, rep = self.run_audit(home)
        self.assertEqual(code, 0)
        self.assertEqual(rep["total"], 1)


class TestMcpServer(unittest.TestCase):
    def rpc(self, *messages):
        p = subprocess.run([sys.executable, str(SUITE / "mcp_server.py")],
                           input="".join(json.dumps(m) + "\n" for m in messages),
                           capture_output=True, text=True, timeout=60)
        return [json.loads(l) for l in p.stdout.splitlines() if l.strip()]

    def test_initialize_and_list_tools(self):
        out = self.rpc(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        )
        self.assertEqual(len(out), 2)  # the notification gets no reply
        self.assertEqual(out[0]["result"]["serverInfo"]["name"], "macguardian")
        names = {t["name"] for t in out[1]["result"]["tools"]}
        for expected in ("run_checkup", "tailscale_doctor", "audit_browser_extensions",
                         "run_software_updates", "get_job"):
            self.assertIn(expected, names)

    def test_unknown_method_and_bad_job(self):
        out = self.rpc(
            {"jsonrpc": "2.0", "id": 1, "method": "nope"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_job", "arguments": {"job_id": "missing"}}},
        )
        self.assertEqual(out[0]["error"]["code"], -32601)
        self.assertTrue(out[1]["result"]["isError"])


if __name__ == "__main__":
    unittest.main()
