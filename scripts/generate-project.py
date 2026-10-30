#!/usr/bin/env python3
"""Generate a dependency-free, local macOS Xcode app project."""
from pathlib import Path
import hashlib
import plistlib

root = Path(__file__).resolve().parent.parent
project = root / "SafeCleaner.xcodeproj"
project.mkdir(exist_ok=True)

def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def q(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

files = sorted(root.glob("Sources/**/*.swift"))
objects = []
def obj(name, body):
    objects.append(f"\t\t{uid(name)} = {{ {body} }};")

def array(items):
    return "(" + ", ".join(items) + ")"

for file in files:
    path = str(file.relative_to(root))
    obj("ref:" + path, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;")
    obj("build:" + path, f"isa = PBXBuildFile; fileRef = {uid('ref:' + path)};")
obj("product", "isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SafeCleaner.app; sourceTree = BUILT_PRODUCTS_DIR;")
obj("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(uid('build:' + str(f.relative_to(root))) for f in files)}; runOnlyForDeploymentPostprocessing = 0;")
obj("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
obj("assets-ref", "isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = SOURCE_ROOT;")
obj("assets-build", f"isa = PBXBuildFile; fileRef = {uid('assets-ref')};")
obj("privacy-ref", "isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;")
obj("privacy-build", f"isa = PBXBuildFile; fileRef = {uid('privacy-ref')};")
obj("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid('assets-build')}, {uid('privacy-build')}); runOnlyForDeploymentPostprocessing = 0;")
obj("products", f"isa = PBXGroup; children = ({uid('product')}); name = Products; sourceTree = \"<group>\";")
def source_group(directory):
    entries = []
    for child in sorted(directory.iterdir()):
        if child.is_dir():
            entries.append(source_group(child))
        elif child.suffix == ".swift":
            entries.append(uid("ref:" + str(child.relative_to(root))))
    name = "folder:" + str(directory.relative_to(root))
    obj(name, f"isa = PBXGroup; children = {array(entries)}; name = {q(directory.name)}; sourceTree = \"<group>\";")
    return uid(name)

children = [source_group(root / "Sources"), uid("assets-ref"), uid("privacy-ref"), uid("products")]
obj("group", f"isa = PBXGroup; children = {array(children)}; sourceTree = \"<group>\";")

for config in ["Debug", "Release"]:
    common = {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0",
              "CLANG_ENABLE_MODULES": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17"}
    if config == "Debug":
        common.update(SWIFT_OPTIMIZATION_LEVEL="-Onone", DEBUG_INFORMATION_FORMAT="dwarf", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG")
    else:
        common.update(SWIFT_OPTIMIZATION_LEVEL="-O", DEBUG_INFORMATION_FORMAT="dwarf-with-dsym")
    app = {"PRODUCT_NAME": "SafeCleaner", "PRODUCT_BUNDLE_IDENTIFIER": "com.loshi.safecleaner",
           "INFOPLIST_FILE": "Info.plist", "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
           "ENABLE_APP_SANDBOX": "NO", "ENABLE_HARDENED_RUNTIME": "YES",
           "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
           "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "COMBINE_HIDPI_IMAGES": "YES"}
    for prefix, values in [("project", common), ("app", app)]:
        settings = " ".join(f"{key} = {q(value)};" for key, value in values.items())
        obj(prefix + config, f"isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};")
for prefix in ["project", "app"]:
    obj(prefix + "configs", f"isa = XCConfigurationList; buildConfigurations = ({uid(prefix + 'Debug')}, {uid(prefix + 'Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
obj("target", f"isa = PBXNativeTarget; buildConfigurationList = {uid('appconfigs')}; buildPhases = ({uid('sources')}, {uid('frameworks')}, {uid('resources')}); buildRules = (); dependencies = (); name = SafeCleaner; productName = SafeCleaner; productReference = {uid('product')}; productType = \"com.apple.product-type.application\";")
obj("project", f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid('projectconfigs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid('group')}; productRefGroup = {uid('products')}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({uid('target')});")
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n")

schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="SafeCleaner.app" BlueprintName="SafeCleaner" ReferencedContainer="container:SafeCleaner.xcodeproj"/>'
(schemes / "SafeCleaner.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

info = dict(CFBundleName="SafeCleaner", CFBundleDisplayName="SafeCleaner",
            CFBundleIdentifier="com.loshi.safecleaner", CFBundleExecutable="SafeCleaner",
            CFBundlePackageType="APPL", CFBundleShortVersionString="0.5.7", CFBundleVersion="14",
            LSMinimumSystemVersion="14.0", NSHighResolutionCapable=True,
            NSPrincipalClass="NSApplication", CFBundleIconFile="AppIcon",
            CFBundleIconName="AppIcon",
            LSApplicationCategoryType="public.app-category.developer-tools",
            NSHumanReadableCopyright="Copyright © 2026 Taulant Loshi. All rights reserved.",
            # macOS shows its own prompt for these three the first time the app reads them,
            # but only if the reason is declared here. Full Disk Access has no such prompt;
            # the app can only explain it and deep-link to Settings.
            NSDesktopFolderUsageDescription=(
                "SafeCleaner looks for build output and caches in folders you add. "
                "It never moves anything without you reviewing and confirming it first."),
            NSDocumentsFolderUsageDescription=(
                "SafeCleaner looks for build output and caches in folders you add. "
                "It never moves anything without you reviewing and confirming it first."),
            NSDownloadsFolderUsageDescription=(
                "SafeCleaner reports what Downloads is using so it is not invisible to you. "
                "It never moves anything without you reviewing and confirming it first."))
with (root / "Info.plist").open("wb") as f:
    plistlib.dump(info, f)
print("Generated SafeCleaner.xcodeproj and Info.plist")
