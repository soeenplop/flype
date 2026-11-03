import json
import os
import shutil
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
signing = json.loads((ROOT / "shared/Config/Signing.json").read_text())
bundle = Path(os.environ.get("FLYPE_APP_PATH", "build/macos/Flype.app")) / "Contents"
info = {
    "CFBundleDevelopmentRegion": "de", "CFBundleLocalizations": ["de", "en", "fr", "it", "es", "nl"],
    "CFBundleIdentifier": signing["macOSBundleID"], "CFBundleName": "Flype", "CFBundleDisplayName": "Flype",
    "CFBundleIconFile": "Flype.icns", "CFBundleExecutable": "Flype", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "26.0", "NSMicrophoneUsageDescription": "Flype nimmt deine Stimme auf, wenn du eine Transkription startest.",
    "CFBundleURLTypes": [{"CFBundleURLName": "one.binda.flype.mac.auth", "CFBundleURLSchemes": ["flype-mac"]}],
    "NSPrincipalClass": "NSApplication", "ITSAppUsesNonExemptEncryption": False,
    "LSApplicationCategoryType": "public.app-category.productivity", "CFBundleSupportedPlatforms": ["MacOSX"],
    "NSHumanReadableCopyright": "© 2026 binda UG (haftungsbeschränkt)",
}
(bundle / "Info.plist").write_bytes(plistlib.dumps(info))

shutil.copytree(ROOT / "shared/Resources", bundle / "Resources", dirs_exist_ok=True)
