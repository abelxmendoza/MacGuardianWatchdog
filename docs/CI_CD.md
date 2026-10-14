# CI

MacGuardian uses GitHub Actions. Workflows live in `.github/workflows/`.

## `ci.yml` — every push and pull request to `main` / `develop`

| Job | What it checks |
|---|---|
| Syntax Validation | `bash -n` on every shell script (including `install.sh`, `uninstall.sh`, `build_app.sh`) and `py_compile` on every Python file |
| Unit / Integration Tests | BATS suites under `MacGuardianSuite/tests/unit` and `integration` |
| Functional Tests | `MacGuardianSuite/tests/run_all_tests.sh` and `test_self_check.sh` |
| End-to-End Tests | `MacGuardianSuite/tests/e2e/test_full_installation.sh` |
| Security Scan | input-injection tests and a scan for committed credentials (cloud keys, private keys, tokens, hard-coded password values) |
| Build Check | builds and packages the app with `build_app.sh` (`SKIP_INSTALL=1`), verifies its code signature and that it is linked to its scripts |
| Code Linting | shellcheck (advisory) |
| Test Summary | fails the run if any required job failed |

All tests run against a throwaway `$HOME`, never the real `~/.macguardian`.

## `daily-tests.yml`

Runs the test suites on a schedule.

## Running the checks locally

```bash
cd MacGuardianSuite/tests
bash run_all_tests.sh
bash e2e/test_full_installation.sh
bash security/test_input_injection.sh
bash test_self_check.sh
cd ../.. && SKIP_INSTALL=1 ./MacGuardianSuiteUI/build_app.sh
```

## Releases

See [RELEASE.md](../RELEASE.md).
