# Release Guide

MacGuardian is distributed as source: the download on the CERBERUS site is
GitHub's zip archive of one commit, and `install.sh` builds the app on the
user's Mac. There is no signed or notarized binary (see
[SECURITY.md](SECURITY.md#known-limitations)).

## Before releasing

1. Make sure CI is green on `main`
   ([Actions](https://github.com/abelxmendoza/MacGuardianWatchdog/actions)).
   It checks script syntax, runs the functional, end-to-end, security and
   self-check tests, scans for committed secrets, and builds and packages the app.
2. On a Mac, run `./install.sh` from a clean clone and confirm the self-check
   at the end reports no failures.

## Publishing a release

1. Pick the commit (normally the latest on `main`):

   ```bash
   SHA=$(git rev-parse HEAD)
   ```

2. Download GitHub's archive of that commit and compute its checksum:

   ```bash
   curl -sSL -o mg.zip "https://github.com/abelxmendoza/MacGuardianWatchdog/archive/$SHA.zip"
   shasum -a 256 mg.zip
   ls -lh mg.zip
   ```

3. In the CERBERUS site repo, update the `macos` entry in
   `src/data/releases.ts`: `version` (short SHA), `downloadUrl`, `checksum`,
   `fileSize` and `releaseDate`. Run `npm test` there, then push.

GitHub's commit archives are stable, so the published checksum keeps matching.
Users verify their download against it as described in
[SECURITY.md](SECURITY.md#verifying-your-download).

## Version numbering

Releases are identified by commit SHA. The app's displayed version is set in
`MacGuardianSuiteUI/build_app.sh` (`CFBundleShortVersionString`).
