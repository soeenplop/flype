#!/usr/bin/env python3
"""Select only a valid development certificate belonging to the configured team."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEAM = json.loads((ROOT / "shared/Config/Signing.json").read_text())["teamID"]

def development_identity():
    valid = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True, check=True).stdout
    valid_hashes = set(re.findall(r"\b[0-9A-F]{40}\b", valid))
    certificates = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"], capture_output=True, text=True, check=True).stdout
    requested = os.environ.get("FLYPE_SIGN_IDENTITY")
    for certificate in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", certificates, re.S):
        details = subprocess.run(["openssl", "x509", "-noout", "-subject", "-fingerprint", "-sha1", "-nameopt", "RFC2253"], input=certificate, capture_output=True, text=True, check=True).stdout
        if not re.search(r"(?:^|,)OU=" + re.escape(TEAM) + r"(?:,|$)", details, re.M):
            continue
        fingerprint = re.search(r"Fingerprint=([0-9A-F:]+)", details)
        if not fingerprint:
            continue
        identity = fingerprint[1].replace(":", "")
        if identity in valid_hashes and (not requested or requested == identity or requested in details):
            return identity
    raise SystemExit("Kein passendes Apple-Entwicklerzertifikat für Team " + TEAM + ". Bitte das binda-Team in Xcode einrichten. Für unsignierte Prüfungen FLYPE_ADHOC_SIGN=1 verwenden.")

if __name__ == "__main__":
    identity = development_identity()
    if "--check" in sys.argv:
        print("Entwicklerzertifikat für binda bestätigt: " + TEAM)
    else:
        app = ROOT / "build/macos/Flype.app"
        subprocess.run(["codesign", "--force", "--options", "runtime", "--entitlements", str(ROOT / "macos/Flype.entitlements"), "--sign", identity, str(app)], check=True)
        details = subprocess.run(["codesign", "--display", "--verbose=4", str(app)], capture_output=True, text=True, check=True)
        if "TeamIdentifier=" + TEAM not in details.stderr.splitlines():
            raise SystemExit("Signatur gehört nicht zum konfigurierten Team.")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
