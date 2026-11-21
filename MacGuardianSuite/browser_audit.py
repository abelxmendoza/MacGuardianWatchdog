#!/usr/bin/env python3
"""Audit Chrome-family and Firefox extensions for risky add-ons.

Read-only: it never changes a browser profile. Prints a human summary, or
JSON with --json. Exit code 0 = nothing to remove, 1 = something flagged.

Risk rules (kept simple and explainable):
  remove  - on the known-bad list, an impostor of a retired extension, or a
            free VPN/proxy extension (they route or inspect all traffic)
  review  - can read every site AND your cookies, with no author or homepage
  ok      - everything else
"""
import glob
import json
import os
import sys

HOME = os.path.expanduser("~")

# Extensions seen in the wild that should go. Keyed by ID; the value says why.
KNOWN_BAD_IDS = {
    # Chrome
    "llbcnfanfmjhpedaedhbcnpgeepdnnok": "Anonymous 'Online Security' extension with cookie and all-site access",
    "ikclbgejgcbdlhjmckecmdljlpbhmbmf": "Copycat 'HTTPS Everywhere' (the real EFF extension was retired in 2023)",
    "eefofopjefcjhpnpmpbcbalkmebjapcf": "Anonymous 'web protection' extension with all-site access",
    "bihmplhobchoageeokmgbdihknkjbknd": "Free VPN extension (Touch VPN) that routes your traffic",
    # Firefox
    "jid1-93CWPmRbVPjRQA@jetpack": "Honey: known for swapping affiliate cookies",
}

# Name fragments that are risky whatever the ID.
RISKY_NAME_PARTS = {
    "free vpn": "Free VPN extensions route or inspect all your traffic",
    "touch vpn": "Free VPN extensions route or inspect all your traffic",
    "openvpn server finder": "Free VPN finder extensions route or inspect traffic",
    "youtube converter": "Video-converter extensions often ship adware",
    "youtube downloader": "Video-downloader extensions often ship adware",
}

# The real IDs of famous extensions; same name + different ID = impostor.
GENUINE_IDS = {
    "https everywhere": {"gcbommkclmclpchllfjekcdonpmejbdp", "https-everywhere@eff.org"},
    "ublock origin": {"cjpalhdlnbpafiamejdnhcphjbkeiagm", "uBlock0@raymondhill.net"},
    "metamask": {"nkbihfbeogaeaoehlefnkodbefgpgknn", "webextension@metamask.io"},
}

# Big-publisher extensions that need broad access by design; never flag for "review".
KNOWN_GOOD_IDS = {
    "efaidnbmnnnibpcajpcglclefindmkaj",  # Adobe Acrobat
    "jdoahkhfkeipblhbhppmcbdgapeoaopa",  # JumpCloud Go
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa",  # 1Password
    "nngceckbapebfimnlniiiahkandclblb",  # Bitwarden
    "pioclpoplcdbaefihamjohnefbikjilc",  # Evernote Web Clipper
    "nkbihfbeogaeaoehlefnkodbefgpgknn",  # MetaMask
    "cjpalhdlnbpafiamejdnhcphjbkeiagm",  # uBlock Origin
    "pkehgijcmpdhfbdbbnkijodmdjhbjlgp",  # Privacy Badger
}

BROAD_HOSTS ={"<all_urls>", "*://*/*", "http://*/*", "https://*/*"}

CHROMIUM_BROWSERS = {
    "Chrome": "Library/Application Support/Google/Chrome",
    "Brave": "Library/Application Support/BraveSoftware/Brave-Browser",
    "Edge": "Library/Application Support/Microsoft Edge",
    "Arc": "Library/Application Support/Arc/User Data",
}


def localized_name(manifest, version_dir):
    name = manifest.get("name", "")
    if not name.startswith("__MSG_"):
        return name
    key = name[6:-2].lower()
    for loc in (manifest.get("default_locale", "en"), "en", "en_US"):
        path = os.path.join(version_dir, "_locales", loc, "messages.json")
        try:
            with open(path, encoding="utf-8-sig") as fh:
                msgs = {k.lower(): v for k, v in json.load(fh).items()}
            if key in msgs:
                return msgs[key].get("message", name)
        except (OSError, ValueError):
            continue
    return name


def classify(ext_id, name, all_sites, cookies, anonymous):
    lname = name.lower()
    if ext_id in KNOWN_BAD_IDS:
        return "remove", KNOWN_BAD_IDS[ext_id]
    for famous, ids in GENUINE_IDS.items():
        if famous in lname and ext_id not in ids:
            return "remove", f"Impostor: not the real {famous.title()} extension"
    for part, why in RISKY_NAME_PARTS.items():
        if part in lname:
            return "remove", why
    if all_sites and cookies and anonymous and ext_id not in KNOWN_GOOD_IDS:
        return "review", "Can read every site and your cookies, and lists no author or homepage"
    return "ok", ""


def chromium_extensions():
    found = []
    for browser, rel in CHROMIUM_BROWSERS.items():
        base = os.path.join(HOME, rel)
        for ext_root in sorted(glob.glob(os.path.join(base, "*", "Extensions"))):
            profile = os.path.basename(os.path.dirname(ext_root))
            for ext_dir in sorted(glob.glob(os.path.join(ext_root, "*"))):
                manifests = sorted(glob.glob(os.path.join(ext_dir, "*", "manifest.json")))
                if not manifests:
                    continue
                try:
                    with open(manifests[-1], encoding="utf-8-sig") as fh:
                        m = json.load(fh)
                except (OSError, ValueError):
                    continue
                ext_id = os.path.basename(ext_dir)
                if m.get("theme") or ext_id == "nmmhkkegccagdldgiimedpiccmgmieda":
                    continue  # themes and the built-in Web Store payments helper
                name = localized_name(m, os.path.dirname(manifests[-1]))
                perms = [p for p in m.get("permissions", []) + m.get("host_permissions", []) if isinstance(p, str)]
                scripts = m.get("content_scripts", [])
                script_hosts = {h for cs in scripts for h in cs.get("matches", [])}
                all_sites = bool(BROAD_HOSTS & (set(perms) | script_hosts))
                cookies = "cookies" in perms
                anonymous = not (m.get("author") or m.get("homepage_url"))
                verdict, why = classify(ext_id, name, all_sites, cookies, anonymous)
                found.append({
                    "browser": browser, "profile": profile, "id": ext_id, "name": name,
                    "version": m.get("version", ""), "enabled": True,
                    "all_sites": all_sites, "cookies": cookies,
                    "verdict": verdict, "reason": why,
                    "remove_hint": f"{browser.lower()}://extensions/?id={ext_id}" if browser != "Arc" else "arc://extensions",
                })
    return found


def firefox_extensions():
    found = []
    for path in sorted(glob.glob(os.path.join(HOME, "Library/Application Support/Firefox/Profiles/*/extensions.json"))):
        profile = os.path.basename(os.path.dirname(path))
        try:
            with open(path, encoding="utf-8") as fh:
                addons = json.load(fh).get("addons", [])
        except (OSError, ValueError):
            continue
        for a in addons:
            if a.get("type") != "extension" or a.get("location") != "app-profile":
                continue
            if a.get("id", "").endswith("@mozilla.org"):
                continue
            name = (a.get("defaultLocale") or {}).get("name", a.get("id", ""))
            perms = (a.get("userPermissions") or {})
            origins = set(perms.get("origins", []) or [])
            all_sites = bool(BROAD_HOSTS & origins)
            cookies = "cookies" in (perms.get("permissions", []) or [])
            anonymous = not ((a.get("defaultLocale") or {}).get("creator") or (a.get("defaultLocale") or {}).get("homepageURL"))
            # A path that no longer exists means it was already removed.
            if a.get("path") and not os.path.exists(a["path"]):
                continue
            verdict, why = classify(a.get("id", ""), name, all_sites, cookies, anonymous)
            found.append({
                "browser": "Firefox", "profile": profile, "id": a.get("id", ""), "name": name,
                "version": a.get("version", ""), "enabled": bool(a.get("active")),
                "all_sites": all_sites, "cookies": cookies,
                "verdict": verdict, "reason": why, "remove_hint": "about:addons",
            })
    return found


def hijack_checks():
    """Browser policies and configuration profiles are how adware locks settings."""
    issues = []
    for plist in ("/Library/Managed Preferences/com.google.Chrome.plist",
                  os.path.join(HOME, "Library/Preferences/com.google.Chrome.plist")):
        if os.path.exists(plist):
            try:
                import plistlib
                with open(plist, "rb") as fh:
                    data = plistlib.load(fh)
                forced = [k for k in data if k in ("ExtensionInstallForcelist", "HomepageLocation",
                                                   "DefaultSearchProviderSearchURL", "ProxySettings")]
                if forced:
                    issues.append(f"Chrome policy in {plist} sets: {', '.join(forced)}")
            except Exception:
                pass
    ff_policy = "/Applications/Firefox.app/Contents/Resources/distribution/policies.json"
    if os.path.exists(ff_policy):
        issues.append(f"Firefox enterprise policy file present: {ff_policy}")
    return issues


def main():
    as_json = "--json" in sys.argv
    exts = chromium_extensions() + firefox_extensions()
    flagged = [e for e in exts if e["verdict"] != "ok"]
    report = {
        "total": len(exts),
        "remove": [e for e in exts if e["verdict"] == "remove"],
        "review": [e for e in exts if e["verdict"] == "review"],
        "hijack_issues": hijack_checks(),
        "extensions": exts,
    }
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Checked {len(exts)} browser extensions.")
        for label in ("remove", "review"):
            for e in report[label]:
                print(f"{'REMOVE' if label == 'remove' else 'REVIEW'}  {e['browser']} ({e['profile']}): {e['name']} - {e['reason']}")
                print(f"        remove it at {e['remove_hint']}")
        for issue in report["hijack_issues"]:
            print(f"WARN  {issue}")
        if not flagged and not report["hijack_issues"]:
            print("No risky extensions or browser hijacks found.")
    sys.exit(1 if (report["remove"] or report["hijack_issues"]) else 0)


if __name__ == "__main__":
    main()
