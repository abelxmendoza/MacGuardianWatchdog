# Security Policy

## Supported Versions

We currently support the following macOS versions:
- macOS 12 (Monterey) and later
- macOS 13 (Ventura)
- macOS 14 (Sonoma)
- macOS 15 (Sequoia)

## Reporting a Vulnerability

If you discover a security vulnerability in MacGuardian Suite, please report it responsibly:

1. **Do NOT** open a public GitHub issue
2. Email security details to: [Your Security Email]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide an update on the status within 7 days.

## Security Best Practices

### Auto-Fix Safety

- **Default Behavior**: All remediation runs in **dry-run mode** by default
- **Quarantine System**: Files are moved to quarantine (`~/MacGuardian/quarantine/`) instead of being deleted
- **Rollback Capability**: All changes are tracked in JSON manifests with SHA-256 checksums
- **Confirmation Required**: Dangerous operations (file removal, process termination) require explicit confirmation

### Permissions Required

MacGuardian Suite requires the following macOS permissions:

1. **Full Disk Access** (for file integrity monitoring)
   - Required for: File scanning, baseline creation, change detection
   - How to grant: System Settings > Privacy & Security > Full Disk Access

2. **Network Access** (for threat intelligence and reporting)
   - Required for: Downloading threat feeds, sending email reports
   - How to grant: System Settings > Privacy & Security > Network Access

3. **Accessibility** (optional, for some advanced features)
   - Required for: Process monitoring (if enabled)
   - How to grant: System Settings > Privacy & Security > Accessibility

### Data Collection

**What we collect:**
- Security scan results (stored locally)
- Performance metrics (execution times, resource usage)
- Error logs (for troubleshooting)
- Threat intelligence IOCs (IPs, domains, hashes)

**What we DON'T collect:**
- Personal files or content
- Passwords or credentials
- Browsing history
- Application data

**Data Storage:**
- All data is stored locally in `~/Library/Application Support/MacGuardian/`
- No data is transmitted to external servers (except email reports if configured)
- Threat intelligence feeds are downloaded from public sources (Abuse.ch, etc.)

**Data Retention:**
- Scan results: 90 days (configurable)
- Logs: 30 days (configurable)
- Quarantined files: Until manually restored or deleted
- Performance data: 30 days

### Opt-Out Options

You can disable data collection by:
1. Setting `PRIVACY_MODE=minimal` in `config.sh`
2. Disabling specific features in Privacy Mode settings
3. Running with `--no-logging` flag (where supported)

## Security Features

### File Integrity Monitoring (FIM)
- SHA-256 checksums for baseline files
- Change detection with timestamps
- Honeypot file monitoring
- Extended attributes for metadata

### Threat Detection
- Process monitoring (heuristic-based)
- Network connection analysis
- File system anomaly detection
- Command & control (C2) detection

### Remediation Safety
- Dry-run by default
- Quarantine before deletion
- Rollback manifests
- Checksum verification

## Known Limitations

1. **Root Access**: Some features require `sudo` privileges. The suite will prompt when needed.
2. **False Positives**: Heuristic-based detection may flag benign files. Review quarantined files before permanent deletion.
3. **macOS Updates**: Some checks may need updates after major macOS releases.
4. **Third-Party Tools**: Relies on ClamAV, rkhunter, and other tools that must be kept updated.

## Security Updates

We recommend:
- Running `./MacGuardianSuite/mac_guardian.sh` weekly for updates
- Keeping ClamAV definitions updated (`freshclam`)
- Reviewing quarantined files regularly
- Checking for suite updates on GitHub

## Disclosure Policy

Security vulnerabilities will be disclosed:
- After a fix is available (coordinated disclosure)
- With credit to the reporter (if desired)
- In the CHANGELOG and release notes

## Contact

For security concerns: [Your Security Email]
For general support: Open a GitHub issue



---

## App-Level Security Features

# 🔒 MacGuardian Suite App Security

## Overview

MacGuardian Suite now includes comprehensive security features to protect the app itself. A security app should be secure, and we've implemented multiple layers of protection.

## Security Features

### 1. **Secure Password Storage (Keychain)**

**Problem**: Passwords were previously stored in UserDefaults (plaintext)

**Solution**: All passwords now stored in macOS Keychain
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for maximum security
- Encrypted at rest by macOS
- Only accessible by the app
- Automatic audit logging of access

**Implementation**:
- `SecureStorage.swift` - Keychain wrapper
- Passwords automatically migrated from UserDefaults
- SMTP passwords stored securely

### 2. **File Integrity Verification**

**Problem**: Scripts could be tampered with, compromising security

**Solution**: SHA-256 checksums verify file integrity
- Calculates checksums for critical files
- Compares against stored baseline
- Detects any modifications
- Warns user if tampering detected

**Implementation**:
- `IntegrityVerifier.swift` - Checksum verification
- `app_security.sh` - Command-line integrity checker
- Automatic verification on app startup
- Verification before script execution

**Critical Files Monitored**:
- `mac_guardian.sh`
- `mac_watchdog.sh`
- `mac_blueteam.sh`
- `mac_remediation.sh`
- `utils.sh`
- `config.sh`

### 3. **Input Validation & Sanitization**

**Problem**: Injection attacks through user inputs

**Solution**: Comprehensive input validation
- Email format validation
- Path sanitization (prevents directory traversal)
- Script path validation (must be within repository)
- Argument sanitization (removes dangerous characters)
- SMTP settings validation

**Implementation**:
- `InputValidator.swift` - All validation logic
- Validates before script execution
- Blocks dangerous paths
- Sanitizes command arguments

**Blocked Characters**:
- `;`, `&`, `|`, `` ` ``, `$`, `(`, `)`, `<`, `>`
- Null bytes
- Path traversal (`../`, `..\\`)

### 4. **Audit Logging**

**Problem**: No visibility into security events

**Solution**: Comprehensive audit trail
- All security events logged
- Timestamped entries
- Separate logs for different event types
- Stored in secure location

**Log Files**:
- `security_audit.log` - Password/keychain operations
- `integrity_audit.log` - File integrity checks
- `validation_audit.log` - Input validation failures

**Location**: `~/Library/Application Support/MacGuardianSuite/audit/`

### 5. **File Permission Verification**

**Problem**: Scripts might not have correct permissions

**Solution**: Automatic permission checking
- Verifies scripts are executable (755)
- Warns if permissions incorrect
- Checks before execution

**Implementation**:
- `IntegrityVerifier.verifyPermissions()`
- `app_security.sh --check-permissions`

### 6. **Security Dashboard**

**Problem**: No visibility into app security status

**Solution**: New Security Dashboard view
- Real-time integrity status
- Security feature status
- File verification results
- One-click integrity check

**Access**: Navigate to "Security" tab in app

## Usage

### Generate Checksums

First time setup - generate baseline checksums:

```bash
cd MacGuardianSuite
./app_security.sh --generate-checksums
```

### Verify Integrity

Check if files have been modified:

```bash
./app_security.sh --verify
```

### Check Permissions

Verify file permissions:

```bash
./app_security.sh --check-permissions
```

### Run All Checks

```bash
./app_security.sh --all
```

## Security Best Practices

1. **Generate Checksums After Installation**
   - Run `app_security.sh --generate-checksums` after installing
   - Store `.checksums.json` securely (consider backing up)

2. **Regular Integrity Checks**
   - App automatically checks on startup
   - Use Security Dashboard for manual checks
   - Run `app_security.sh --verify` periodically

3. **Monitor Audit Logs**
   - Review audit logs regularly
   - Look for suspicious activity
   - Check for failed integrity checks

4. **Keep App Updated**
   - Update checksums after app updates
   - Verify integrity after updates
   - Report any integrity failures

## Security Architecture

```
┌─────────────────────────────────────┐
│      MacGuardian Suite UI           │
├─────────────────────────────────────┤
│  Input Validation → Sanitization    │
│  Path Validation → Execution        │
│  Integrity Check → Verification     │
│  Permission Check → Execution        │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│      Secure Storage Layer           │
├─────────────────────────────────────┤
│  Keychain (Passwords)               │
│  Checksums (Integrity)              │
│  Audit Logs (Events)                │
└─────────────────────────────────────┘
```

## Threat Model

### Protected Against:

✅ **Password Theft**
- Passwords encrypted in Keychain
- Not accessible to other apps
- Audit trail of access

✅ **File Tampering**
- Checksum verification detects changes
- Warns before execution
- Can block execution if configured

✅ **Injection Attacks**
- Input sanitization
- Path validation
- Argument sanitization

✅ **Unauthorized Access**
- Permission verification
- Path restrictions
- Audit logging

### Not Protected Against:

⚠️ **Physical Access**
- If attacker has physical access and admin rights, they can modify files
- Mitigation: Use FileVault encryption

⚠️ **Root Compromise**
- If system is compromised at root level, all protections can be bypassed
- Mitigation: Regular security audits, keep system updated

## Compliance

- **OWASP Top 10**: Addresses injection, broken authentication
- **CIS Controls**: Implements secure configuration, access control
- **NIST Framework**: Implements Protect, Detect functions

## Future Enhancements

- [ ] Code signing verification
- [ ] Network traffic encryption
- [ ] Two-factor authentication for sensitive operations
- [ ] Automated security scanning
- [ ] Security incident response automation

## Reporting Security Issues

If you discover a security vulnerability:

1. **DO NOT** create a public issue
2. Email security concerns to: [Your Security Email]
3. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and coordinate disclosure.



---

## Sudo Security Guide

# 🔒 Passwordless Sudo Security Guide

## Is Passwordless Sudo Safe?

**Short Answer: It reduces security, but can be made safer with proper configuration.**

## Security Risks

### ⚠️ Risks:
1. **No Password Protection**: If someone gains access to your user account, they have full admin access
2. **Malware Impact**: Malware running as your user can escalate to root without password
3. **Physical Access**: If someone has physical access to your Mac, they can run admin commands
4. **Accidental Damage**: Easier to accidentally run destructive commands

### ✅ When It's Relatively Safe:
- **Limited Scope**: Only for specific commands (like `rkhunter`), not all sudo commands
- **Single-User Mac**: No other users on the system
- **FileVault Enabled**: Disk encryption protects against physical access
- **Good Security Practices**: Regular updates, antivirus, firewall enabled

## Safer Alternatives

### Option 1: Command-Specific Passwordless Sudo (Recommended)

Instead of passwordless sudo for everything, only allow it for specific commands:

```bash
sudo visudo
```

Add this line (most secure):
```
abel_elreaper ALL=(ALL) NOPASSWD: /usr/local/bin/rkhunter, /opt/homebrew/bin/rkhunter, /usr/local/bin/rkhunter --update, /opt/homebrew/bin/rkhunter --update
```

**Why this is safer:**
- Only `rkhunter` can run without password
- Other sudo commands still require password
- Limits attack surface

### Option 2: Time-Limited Sudo (Better)

Keep sudo access for a limited time:

```bash
# In Terminal, run:
sudo -v
```

This caches your sudo password for 15 minutes. Then run:
```bash
cd /Users/abel_elreaper/Desktop/MacGuardianProject
./MacGuardianSuite/mac_guardian.sh --resume
```

**Why this is safer:**
- Password still required initially
- Only lasts 15 minutes
- No permanent configuration needed

### Option 3: Run Rootkit Scan Separately (Safest)

Don't configure passwordless sudo at all. Just run rootkit scan manually when needed:

```bash
cd /Users/abel_elreaper/Desktop/MacGuardianProject
sudo ./MacGuardianSuite/rkhunter_scan.sh
```

Or create a simple wrapper script that you run with sudo when needed.

## Best Practices

### ✅ If You Must Use Passwordless Sudo:

1. **Limit to Specific Commands Only**
   ```bash
   # Good: Only specific commands
   username ALL=(ALL) NOPASSWD: /usr/local/bin/rkhunter
   
   # Bad: Everything
   username ALL=(ALL) NOPASSWD: ALL
   ```

2. **Use Full Paths**
   - Always specify full paths to executables
   - Prevents path hijacking attacks

3. **Regular Audits**
   - Review sudoers file periodically
   - Remove entries you no longer need

4. **Enable FileVault**
   - Encrypts disk, protects against physical access

5. **Use Strong User Password**
   - Since sudo doesn't require password, user password becomes more important

### ❌ Don't Do This:

```bash
# NEVER do this - gives passwordless sudo for everything!
username ALL=(ALL) NOPASSWD: ALL
```

## Recommendation for MacGuardian Suite

**For Most Users:**
- **Don't configure passwordless sudo**
- Run rootkit scan manually from Terminal when needed
- Use `sudo -v` to cache password for 15 minutes

**For Advanced Users:**
- If you want automation, use command-specific passwordless sudo
- Only for `rkhunter` commands
- Keep FileVault enabled
- Use strong user password

## Security Comparison

| Method | Security Level | Convenience | Risk |
|--------|---------------|-------------|------|
| Manual sudo (Terminal) | ⭐⭐⭐⭐⭐ Highest | ⭐⭐ Low | ✅ Lowest |
| Time-limited sudo cache | ⭐⭐⭐⭐ High | ⭐⭐⭐ Medium | ✅ Low |
| Command-specific passwordless | ⭐⭐⭐ Medium | ⭐⭐⭐⭐ High | ⚠️ Medium |
| Full passwordless sudo | ⭐ Low | ⭐⭐⭐⭐⭐ Highest | ❌ High |

## Conclusion

**For MacGuardian Suite specifically:**
- Rootkit scan is **optional** - other security checks don't need sudo
- Running it manually from Terminal is the **safest** option
- If you want automation, use **command-specific** passwordless sudo (not full sudo)
- The app works fine without rootkit scan - it's just an extra security check

**Bottom Line:** Passwordless sudo reduces security, but limiting it to specific commands (`rkhunter` only) is relatively safe for a single-user Mac with FileVault enabled. However, running it manually is still the safest option.

