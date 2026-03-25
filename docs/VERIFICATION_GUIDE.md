# Mac Guardian Suite Verification Guide

## Quick Verification

Run the automated verification script:
```bash
./MacGuardianSuite/verify_suite.sh
```

This will test all components and provide a comprehensive report.

## Manual Verification Steps

### 1. **Check All Modules Run Successfully**

Test each module individually:

```bash
# Test Mac Guardian
./MacGuardianSuite/mac_guardian.sh

# Test Mac Blue Team
./MacGuardianSuite/mac_blueteam.sh

# Test Mac AI
./MacGuardianSuite/mac_ai.sh

# Test Mac Security Audit
./MacGuardianSuite/mac_security_audit.sh

# Test Mac Remediation (dry-run)
./MacGuardianSuite/mac_remediation.sh
```

**Expected Results:**
- ✅ Scripts execute without errors
- ✅ Logs are created in `~/.macguardian/`
- ✅ Output shows completion status

### 2. **Verify Logging Works**

Check that logs are being created:
```bash
ls -la ~/.macguardian/
ls -la ~/.macguardian/guardian/
ls -la ~/.macguardian/blueteam/
ls -la ~/.macguardian/ai/
```

**Expected Results:**
- ✅ Log directories exist
- ✅ Recent log files are present
- ✅ Log files contain readable content

### 3. **Test Notifications**

Run a module that should trigger a notification:
```bash
# This should send a notification if issues are found
./MacGuardianSuite/mac_blueteam.sh
```

**Expected Results:**
- ✅ macOS notification appears (if issues detected)
- ✅ Notification shows title and message
- ✅ No notification spam (throttling works)

### 4. **Verify Parallel Processing**

Check that parallel processing is working:
```bash
# Run Blue Team with verbose output
./MacGuardianSuite/mac_blueteam.sh -v
```

**Expected Results:**
- ✅ See "Running analyses in parallel" message
- ✅ Multiple jobs complete successfully
- ✅ No timeout errors
- ✅ Faster execution than sequential mode

### 5. **Test AI/ML Components**

Verify Python ML engines work:
```bash
# Test AI engine
python3 MacGuardianSuite/ai_engine.py --help

# Test ML engine
python3 MacGuardianSuite/ml_engine.py --help

# Run full AI analysis
./MacGuardianSuite/mac_ai.sh
```

**Expected Results:**
- ✅ Python scripts execute without errors
- ✅ ML models load/train successfully
- ✅ Anomaly detection runs
- ✅ Pattern recognition works

### 6. **Verify Security Tools Integration**

Check that security tools are available:
```bash
# ClamAV
clamscan --version

# rkhunter
rkhunter --version

# Check if tools are being used
./MacGuardianSuite/mac_guardian.sh
```

**Expected Results:**
- ✅ Security tools are installed (or auto-installed)
- ✅ Tools are called during scans
- ✅ Scan results are logged

### 7. **Test Error Handling**

Verify graceful error handling:
```bash
# Run with invalid options
./MacGuardianSuite/mac_guardian.sh --invalid-option 2>&1

# Check that errors are logged but don't crash
```

**Expected Results:**
- ✅ Errors are caught and logged
- ✅ Script doesn't crash on errors
- ✅ Helpful error messages displayed

### 8. **Verify Configuration**

Check configuration is loaded:
```bash
# View config
cat MacGuardianSuite/config.sh

# Check if config is being used
grep -r "ENABLE_PARALLEL\|LOG_DIR" ~/.macguardian/*.log | head -5
```

**Expected Results:**
- ✅ Configuration file exists
- ✅ Config values are used in logs
- ✅ Settings can be customized

### 9. **Test Remediation (Dry-Run)**

Verify remediation works safely:
```bash
# Dry-run mode (no changes)
./MacGuardianSuite/mac_remediation.sh

# Check what would be fixed
cat ~/.macguardian/remediation/remediation_*.log | tail -20
```

**Expected Results:**
- ✅ Dry-run shows what would be fixed
- ✅ No actual changes made
- ✅ Logs show remediation actions

### 10. **Performance Check**

Verify performance optimizations:
```bash
# Time a full Blue Team run
time ./MacGuardianSuite/mac_blueteam.sh

# Should complete in reasonable time (< 2 minutes typically)
```

**Expected Results:**
- ✅ Parallel processing speeds up execution
- ✅ No excessive timeouts
- ✅ Efficient resource usage

## What to Look For

### ✅ **Signs Everything is Working:**
- All scripts execute without errors
- Logs are created and updated
- Notifications appear when appropriate (not spamming)
- Parallel jobs complete successfully
- AI/ML analysis produces results
- Security scans complete
- Remediation shows previews correctly

### ⚠️ **Common Issues & Solutions:**

1. **"Command not found" errors**
   - Solution: Run the suite once to auto-install dependencies
   - Or manually: `brew install clamav rkhunter`

2. **Python import errors**
   - Solution: Dependencies auto-install on first AI run
   - Or manually: `pip3 install numpy scikit-learn pandas`

3. **Permission denied**
   - Solution: `chmod +x MacGuardianSuite/*.sh`

4. **Notifications not showing**
   - Solution: Check System Preferences > Notifications
   - Ensure "Do Not Disturb" is off

5. **Timeout errors**
   - Solution: Increase `PARALLEL_JOB_TIMEOUT` in `config.sh`
   - Or disable parallel mode temporarily

## Quick Health Check

Run this one-liner to quickly verify core functionality:
```bash
./MacGuardianSuite/verify_suite.sh && echo "✅ All systems operational!" || echo "⚠️  Some issues detected - check output above"
```

## Detailed Logs

All verification and test logs are saved to:
```
~/.macguardian/verification_YYYYMMDD_HHMMSS.log
```

Review these logs for detailed test results and any issues.

## Need Help?

If verification fails:
1. Check the test log for specific errors
2. Review the module's individual log files
3. Ensure all dependencies are installed
4. Check file permissions
5. Review the configuration file

Most issues are resolved by running the suite once to auto-install dependencies.

