# Security Policy

MacGuardian is a security tool, so it has to be trustworthy itself. This page
explains how to check that the copy you downloaded is genuine, what the
installer and app do on your Mac, how MacGuardian checks its own integrity,
and how to report a problem.

## Reporting a vulnerability

Please report security problems privately, not in a public issue:

- On GitHub, open the repository's **Security** tab and choose **Report a vulnerability**.
- If that option isn't available, open an issue titled "Security contact request"
  **without any details**, and a private channel will be arranged.

Include what you found, how to reproduce it, and what an attacker could do with it.

## Verifying your download

The website lists a SHA-256 checksum for each download. Before unzipping, compare it:

```bash
shasum -a 256 ~/Downloads/MacGuardianWatchdog-*.zip
```

The output must match the checksum on the download page exactly. If it doesn't,
delete the file and download it again; don't run anything from it.

You can also read every script before running it: the download is the source
code itself, and the app is built on your Mac from that source by `install.sh`.

## What the installer does

`install.sh` (or double-clicking **Install MacGuardian.command**):

- **Never uses `sudo`** and never asks for your password. If something needs
  administrator rights (accepting the Xcode license, for example), it stops and
  shows you the exact command to run yourself.
- Copies a downloaded zip to `~/Library/Application Support/MacGuardian/Suite`
  (a git clone stays where it is) and clears the browser's quarantine flag on
  those files only.
- Builds the app from source with Xcode and installs it to `/Applications`,
  signed with a local ad-hoc signature.
- Only asks before installing anything else: ClamAV and rkhunter through
  Homebrew, the real-time monitor, and scheduled checks.
- Records SHA-256 fingerprints of every MacGuardian script in
  `~/.macguardian/install_manifest.sha256` (see Self-check below).

Network access during install: Homebrew (only if you accept the scanners),
`freshclam` virus definitions (only if you accept), and Swift Package Manager
fetching the one dependency, [Yams](https://github.com/jpsim/Yams), at the
version pinned in `MacGuardianSuiteUI/Package.resolved`.

`uninstall.sh` removes the app, every MacGuardian background job and its
private script copy; your results in `~/.macguardian` are kept unless you ask.

## What the app does on your Mac

- **Everything stays local.** Scan results, reports and logs are written to
  `~/.macguardian`. Nothing is uploaded, and there is no telemetry.
- **Network use is opt-in only:** threat-feed downloads from abuse.ch when you
  run `threat_intel_feeds.sh`; email reports only if you configure SMTP;
  webhooks, Splunk and fleet mode only if you configure an endpoint.
- **The app stores your SMTP password in the macOS Keychain**, never in a
  file. (The command-line email scripts read `SMTP_PASSWORD` from your
  environment instead, if you choose to set it there.)
- **Email goes only to the address you configure** in
  `~/.macguardian/config.conf`; there is no built-in recipient.
- **Destructive actions are previewed first.** Remediation defaults to a dry
  run, quarantined files go to `~/MacGuardian/quarantine` (restorable) rather
  than being deleted, and force-quitting apps or cleaning caches asks first.
- **Administrator rights are only used where macOS requires them** (the
  rootkit scan), and those commands open in Terminal so you see and approve
  them. MacGuardian never configures passwordless `sudo`.
- **Background jobs run a private copy** of the scripts from
  `~/Library/Application Support/MacGuardian`, because macOS blocks background
  jobs from reading Desktop, Documents and Downloads.

## Self-check

MacGuardian checks its own security posture at every launch (the result is the
first card on the Dashboard) and on demand under **Audit → Self-Check**, or from
Terminal:

```bash
MacGuardianSuite/self_check.sh
```

It checks that:

1. **Every script matches the fingerprint recorded at install.** Any changed,
   added or missing script is reported. The fingerprints are kept in
   `~/.macguardian`, outside the project folder, so they can't be quietly
   rewritten alongside the scripts.
2. **No other user can modify MacGuardian's files.** Group- or world-writable
   files and files owned by someone else are reported, since they could change
   what MacGuardian runs.
3. **The installed app's code signature is intact** and the app runs the
   scripts in this folder.
4. **Background jobs are safe and current:** their definitions aren't writable
   by others, the scripts they run exist, aren't in a folder macOS blocks, and
   match the current version.
5. **Your data stays private:** `~/.macguardian` is readable only by you and
   holds no plain-text passwords.

After you update MacGuardian (or edit its scripts yourself), run `install.sh`
again so the new versions become the trusted baseline.

## Known limitations

- The app is **not notarized by Apple** and has an ad-hoc signature, because
  it is built on your Mac rather than distributed as a signed binary. macOS
  trusts it because you built it locally.
- The self-check detects changes **after** install. Verifying the download
  checksum (above) is what establishes trust in the copy you install.
- Someone who already controls your user account could also rewrite the
  baseline. The self-check protects against tampering by other users,
  processes and accidental changes, not against a fully compromised account.
- MacGuardian reduces risk and makes problems visible. It does not guarantee
  protection against all malware or attacks.

## Supported versions

- App: macOS 14 (Sonoma) and later, built with the full Xcode.
- Shell tools: macOS 12 (Monterey) and later.
