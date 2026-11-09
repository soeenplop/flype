#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Run again after adding Swift files."""
import hashlib
import plistlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIGNING = json.loads((ROOT / "shared/Config/Signing.json").read_text())
IOS = ROOT / "ios"
PROJECT = IOS / "Flype.xcodeproj"
PROJECT.mkdir(exist_ok=True)

# Keep signing choices made in Xcode when the project is regenerated.
existing_objects = {}
existing_project = PROJECT / "project.pbxproj"
if existing_project.exists():
    parsed = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(existing_project)], capture_output=True)
    if parsed.returncode == 0:
        existing_objects = json.loads(parsed.stdout).get("objects", {})

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

def ref(name):
    return uid(name)

def array(values):
    return "(" + ", ".join(values) + ")"

objects = {}

def obj(identifier, isa, **values):
    objects[uid(identifier)] = {"isa": isa, **values}
    return uid(identifier)

# Group name -> folder, relative to the project. Shared/App is compiled directly into the app target.
folders = {"App": "App", "Keyboard": "Keyboard", "SharedApp": "../shared/App"}
sources = {group: sorted((IOS / folder).glob("*.swift")) for group, folder in folders.items()}
for group, paths in sources.items():
    for path in paths:
        name = str(path.relative_to(ROOT))
        obj(name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=quote(path.name), sourceTree='"<group>"')
    obj("group-" + group, "PBXGroup", children=array([ref(str(p.relative_to(ROOT))) for p in paths]), path=quote(folders[group]), sourceTree='"<group>"')

for product, filetype in (("Flype.app", "wrapper.application"), ("FlypeKeyboard.appex", "wrapper.app-extension")):
    obj(product, "PBXFileReference", explicitFileType=filetype, includeInIndex="0", path=quote(product), sourceTree="BUILT_PRODUCTS_DIR")
obj("products", "PBXGroup", children=array([ref("Flype.app"), ref("FlypeKeyboard.appex")]), name="Products", sourceTree='"<group>"')
obj("root", "PBXGroup", children=array([ref("group-" + f) for f in sources] + [ref("group-resources"), ref("group-wordlists"), ref("products")]), sourceTree='"<group>"')

info_children = []
for language in ("de", "en", "fr", "it", "es", "nl"):
    info_children.append(obj("info-" + language, "PBXFileReference", lastKnownFileType="text.plist.strings", name=quote(language), path=quote(language + ".lproj/InfoPlist.strings"), sourceTree='"<group>"'))
obj("localized-info", "PBXVariantGroup", children=array(info_children), name=quote("InfoPlist.strings"), sourceTree='"<group>"')
obj("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path=quote("Assets.xcassets"), sourceTree='"<group>"')
obj("assets-build", "PBXBuildFile", fileRef=ref("assets"))
obj("privacy", "PBXFileReference", lastKnownFileType="text.xml", path=quote("PrivacyInfo.xcprivacy"), sourceTree='"<group>"')
obj("privacy-app-build", "PBXBuildFile", fileRef=ref("privacy"))
obj("privacy-keyboard-build", "PBXBuildFile", fileRef=ref("privacy"))
obj("group-resources", "PBXGroup", children=array([ref("localized-info"), ref("assets"), ref("privacy")]), path=quote("../shared/Resources"), sourceTree='"<group>"')
obj("info-build", "PBXBuildFile", fileRef=ref("localized-info"))
# Word lists for swipe typing. The keyboard finds them by language, so a new language only needs its file.
word_lists = sorted((ROOT / "vendor/HeliBoardDictionaries").glob("*.combined"))
for path in word_lists:
    obj("wordlist-" + path.name, "PBXFileReference", lastKnownFileType="text", path=quote(path.name), sourceTree='"<group>"')
    obj("wordlist-build-" + path.name, "PBXBuildFile", fileRef=ref("wordlist-" + path.name))
obj("group-wordlists", "PBXGroup", children=array([ref("wordlist-" + p.name) for p in word_lists]), path=quote("../vendor/HeliBoardDictionaries"), sourceTree='"<group>"')

base = {
    "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete", "TARGETED_DEVICE_FAMILY": '"1,2"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1",
}

def settings(values):
    return "{ " + " ".join(f"{k} = {v};" for k, v in sorted(values.items())) + " }"

for target in ("project", "app", "keyboard"):
    for config in ("Debug", "Release"):
        build = dict(base) if target == "project" else {}
        if target == "project":
            if config == "Debug":
                build["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = '"$(inherited) DEBUG"'
            build.update({"SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if config == "Debug" else '"-O"',
                          "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else '"dwarf-with-dsym"',
                          "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO"})
        else:
            folder = "App" if target == "app" else "Keyboard"
            build.update({
                "PRODUCT_NAME": "Flype" if target == "app" else "FlypeKeyboard",
                "DEVELOPMENT_TEAM": quote(SIGNING["teamID"]),
                "PRODUCT_BUNDLE_IDENTIFIER": quote(SIGNING["iOSBundleID"] if target == "app" else SIGNING["keyboardBundleID"]),
                "INFOPLIST_FILE": quote(folder + "/Info.plist"),
                "CODE_SIGN_ENTITLEMENTS": quote(folder + "/Flype.entitlements"),
                "GENERATE_INFOPLIST_FILE": "NO",
                "ENABLE_DEBUG_DYLIB": "NO",
                "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"' if target == "app" else '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
            })
            if target == "app":
                build["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            if target == "keyboard":
                build.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES"})
            if target == "keyboard" and config == "Debug":
                host_plugin = '"$(inherited) $(SRCROOT)/../vendor/KeyboardKitHostPlugin/$(PLATFORM_NAME)"'
                build.update({"SWIFT_INCLUDE_PATHS": host_plugin,
                              "LIBRARY_SEARCH_PATHS": host_plugin,
                              "OTHER_LDFLAGS": '"$(inherited) -lKeyboardKitHostPlugin"'})
            existing_build = existing_objects.get(uid(target + config), {}).get("buildSettings", {})
            for key in ("DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER"):
                if existing_build.get(key):
                    build[key] = quote(existing_build[key])
        obj(target + config, "XCBuildConfiguration", buildSettings=settings(build), name=config)
    obj(target + "configs", "XCConfigurationList", buildConfigurations=array([ref(target + c) for c in ("Debug", "Release")]), defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

obj("core-package", "XCLocalSwiftPackageReference", relativePath=quote("../shared/FlypeCore"))
for target in ("app", "keyboard"):
    obj(target + "-core-product", "XCSwiftPackageProductDependency", package=ref("core-package"), productName="FlypeCore")
    obj(target + "-core-link", "PBXBuildFile", productRef=ref(target + "-core-product"))
obj("speech-package", "XCLocalSwiftPackageReference", relativePath=quote("../shared/FlypeSpeech"))
obj("speech-product", "XCSwiftPackageProductDependency", package=ref("speech-package"), productName="FlypeSpeech")
obj("speech-link", "PBXBuildFile", productRef=ref("speech-product"))

obj("proxy", "PBXContainerItemProxy", containerPortal=ref("project"), proxyType="1", remoteGlobalIDString=ref("keyboard"), remoteInfo="FlypeKeyboard")
obj("dependency", "PBXTargetDependency", target=ref("keyboard"), targetProxy=ref("proxy"))
obj("embed-file", "PBXBuildFile", fileRef=ref("FlypeKeyboard.appex"), settings='{ ATTRIBUTES = (RemoveHeadersOnCopy, ); }')
obj("embed", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath='""', dstSubfolderSpec="13", files=array([ref("embed-file")]), name='"Embed App Extensions"', runOnlyForDeploymentPostprocessing="0")

for target, folder, product, product_type in (
    ("app", "App", "Flype.app", "com.apple.product-type.application"),
    ("keyboard", "Keyboard", "FlypeKeyboard.appex", "com.apple.product-type.app-extension"),
):
    files = []
    for path in sources[folder] + (sources["SharedApp"] if target == "app" else []):
        name = str(path.relative_to(ROOT))
        files.append(obj(target + name, "PBXBuildFile", fileRef=ref(name)))
    obj(target + "sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=array(files), runOnlyForDeploymentPostprocessing="0")
    obj(target + "frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=array([ref(target + "-core-link")] + ([ref("speech-link")] if target == "app" else [])), runOnlyForDeploymentPostprocessing="0")
    obj(target + "resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=array([ref("info-build"), ref("assets-build"), ref("privacy-app-build")]) if target == "app" else array([ref("privacy-keyboard-build")] + [ref("wordlist-build-" + p.name) for p in word_lists]), runOnlyForDeploymentPostprocessing="0")
    phases = [ref(target + phase) for phase in ("sources", "frameworks", "resources")]
    if target == "app": phases.append(ref("embed"))
    obj(target, "PBXNativeTarget", buildConfigurationList=ref(target + "configs"), buildPhases=array(phases), buildRules="()", dependencies=array([ref("dependency")] if target == "app" else []), name=quote(product.split(".")[0]), productName=quote(product.split(".")[0]), productReference=ref(product), productType=quote(product_type), packageProductDependencies=array([ref(target + "-core-product")] + ([ref("speech-product")] if target == "app" else [])))

obj("project", "PBXProject", attributes='{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }', buildConfigurationList=ref("projectconfigs"), compatibilityVersion='"Xcode 14.0"', developmentRegion="de", hasScannedForEncodings="0", knownRegions="(de, en, fr, it, es, nl, Base)", mainGroup=ref("root"), productRefGroup=ref("products"), packageReferences=array([ref("core-package"), ref("speech-package")]), projectDirPath='""', projectRoot='""', targets=array([ref("app"), ref("keyboard")]))

body = "\n".join(f"\t\t{key} = {{ " + " ".join(f"{k} = {v};" for k, v in values.items()) + " };" for key, values in sorted(objects.items()))
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + body + "\n\t};\n\trootObject = " + ref("project") + ";\n}\n")

scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("app")}" BuildableName="Flype.app" BlueprintName="Flype" ReferencedContainer="container:Flype.xcodeproj"/>'
(scheme_dir / "Flype.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

for folder, name, package in (("App", "Flype", "APPL"), ("Keyboard", "Flype", "XPC!")):
    info = {"CFBundleDevelopmentRegion": "de", "CFBundleLocalizations": ["de", "en", "fr", "it", "es", "nl"], "CFBundleDisplayName": name,
            "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundlePackageType": package, "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"}
    if folder == "App":
        info.update({"LSRequiresIPhoneOS": True,
                     "CFBundleURLTypes": [{"CFBundleURLName": "one.binda.flype.dictation", "CFBundleURLSchemes": ["one.binda.flype", "flype"], "CFBundleTypeRole": "Editor"}],
                     "NSMicrophoneUsageDescription": "Flype nimmt deine Stimme für Transkriptionen auf. Die Aufnahme bleibt auf deinem Gerät.",
                     "UIBackgroundModes": ["audio"],
                     "ITSAppUsesNonExemptEncryption": False,
                     "LSApplicationCategoryType": "public.app-category.productivity",
                     "UILaunchScreen": {},
                     "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
                     "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                     "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]})
    else:
        info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.keyboard-service",
                               "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).KeyboardViewController",
                               "NSExtensionAttributes": {"IsASCIICapable": True, "PrefersRightToLeft": False,
                                                         "PrimaryLanguage": "de-DE", "RequestsOpenAccess": True}}
    (IOS / folder / "Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
    (IOS / folder / "Flype.entitlements").write_bytes(plistlib.dumps({"com.apple.security.application-groups": [SIGNING["appGroupID"]]}))

print("Flype.xcodeproj generated (app + keyboard; Debug-only host resolver).")
