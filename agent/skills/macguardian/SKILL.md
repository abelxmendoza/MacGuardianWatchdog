---
name: macguardian
description: Check, defend and maintain this Mac with MacGuardian Watchdog. Use when the user asks to scan or secure their Mac, check for malware or risky browser extensions, fix Tailscale, see whether the computer is safe, or update their software.
---

# MacGuardian Watchdog

MacGuardian is the user's own macOS security suite. Use it to answer "is my Mac
OK?" with evidence instead of guesses.

## How to run it

Prefer the `macguardian` MCP tools when they are available. Otherwise use the
CLI (`macguardian` is on PATH after install; the scripts live in
`MacGuardianSuite/` of the MacGuardian project).

| Goal | MCP tool | CLI |
| --- | --- | --- |
| Full checkup (everything below) | `run_checkup` (mode `quick`, `standard` or `full`) then `get_job` | `macguardian checkup [--quick\|--full]` |
| Last result | `get_checkup_report` | `macguardian report` |
| Tailscale not working | `tailscale_doctor` | `macguardian tailscale` |
| Risky browser extensions | `audit_browser_extensions` | `macguardian browsers` |
| What needs updating | `check_software_updates` | `macguardian update` |
| Install updates | `run_software_updates` (ask first) | `macguardian upgrade --batch -y` |
| Is MacGuardian itself intact | `self_check` | `macguardian doctor` |

Checkup steps: Tailscale, security posture (FileVault, SIP, Gatekeeper,
firewall, auto security updates, Remote Login), MacGuardian self-check, threat
hunt (processes, network, odd files), ClamAV malware scan (recent downloads +
startup folders; `full` scans all of Downloads), browser extensions, and
software updates. `quick` skips the malware and threat scans and takes about a
minute. Reports land in `~/.macguardian/checkup/latest.json`.

Run long commands in the background (standard checkup is 3-10 minutes,
updates can be an hour) and report when they finish.

## Rules

- Everything is read-only except installing updates. Ask before
  `run_software_updates`, deleting files, removing apps or extensions, or
  changing firewall/network settings. Prefer moving to the Trash over deleting.
- Anything needing `sudo` (stopping a system daemon, `sudo mas upgrade`): give
  the user the exact command in a `bash` block; you cannot type their password.
- Never flag MacGuardian itself (`~/Library/Application Support/MacGuardian`)
  as suspicious.
- If the user runs LuLu or Little Snitch, Homebrew updates trigger a prompt for
  `/opt/homebrew/opt/curl/bin/curl` (downloads from ghcr.io). Tell them to
  allow it once for any address, and use `--batch` so it is one burst.
- Chrome extensions cannot be removed by a script. Give the
  `chrome://extensions/?id=<id>` link from the report, or use a browser tool if
  one is connected. Firefox add-ons can be moved out of the profile's
  `extensions/` folder (to the Trash) while Firefox is closed.
- Separate PASS, WARN, FAIL and SKIP in what you tell the user; a skipped step
  is not a pass.

## Reading results

- **tailscale**: "Two Tailscale daemons" means a Homebrew `tailscaled` is
  fighting the Tailscale app. The fix command in the report stops the Homebrew
  one; then delete the stale duplicate machine in the Tailscale admin console.
  "relay" connections usually mean a firewall is blocking Tailscale's UDP.
- **selfcheck** FAIL right after the user edited MacGuardian's scripts is
  expected: `bash MacGuardianSuite/self_check.sh --record` re-baselines them.
  Otherwise treat it as possible tampering.
- **threats**: each finding is a lead, not a verdict. Look at the file or
  process before calling it malicious (e.g. `.ps1` files in `~/.net/` are .NET
  app extractions and are excluded).
- **browsers**: `remove` = known-bad, impostor or free-VPN extension;
  `review` = reads every site and cookies with no listed author. After removing
  anything that had cookie access, suggest signing out of all sessions on
  important accounts.
- **updates**: counts only. Offer to run them; mention App Store updates need
  `sudo mas upgrade` or the App Store app.
