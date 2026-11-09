#!/usr/bin/env python3
"""Generate the iOS project; all shared references stay relative to the repo."""
from pathlib import Path
import hashlib
import os
import plistlib
import sys
root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
shared = repo / 'modern_UI/Spektrafilm/Spektrafilm/Model'
sources = sorted((root / 'Sources').glob('*.swift')) + [shared / 'StockCatalogCore.swift', shared / 'ParamValue.swift', shared / 'Geometry.swift']
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quote(value): return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
objects = []
def obj(key, body):
    ident = uid(key); objects.append(f'{ident} = {{ {body} }};'); return ident
refs, builds = [], []
for source in sources:
    path = os.path.relpath(source, root)
    ref = obj(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(obj('build:' + path, f'isa = PBXBuildFile; fileRef = {ref};'))
# Both platforms compile the same Icon Composer source; no copied PNG catalog.
icon_path = os.path.relpath(repo / 'modern_UI/Spektrafilm/Spektrafilm/Silverphase.icon', root)
icon_ref = obj('app-icon', f'isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = {quote(icon_path)}; sourceTree = SOURCE_ROOT;')
refs.append(icon_ref)
icon_build = obj('build:app-icon', f'isa = PBXBuildFile; fileRef = {icon_ref};')
privacy_ref = obj('privacy-manifest', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;')
refs.append(privacy_ref)
privacy_build = obj('build:privacy-manifest', f'isa = PBXBuildFile; fileRef = {privacy_ref};')
related_icon_path = os.path.relpath(repo / 'screenshots/related-apps/layerlight-icon.png', root)
related_icon_ref = obj('layerlight-icon', f'isa = PBXFileReference; lastKnownFileType = image.png; path = {quote(related_icon_path)}; sourceTree = SOURCE_ROOT;')
refs.append(related_icon_ref)
related_icon_build = obj('build:layerlight-icon', f'isa = PBXBuildFile; fileRef = {related_icon_ref};')
resource_phase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({icon_build},{privacy_build},{related_icon_build}); runOnlyForDeploymentPostprocessing = 0;')
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Silverphase.app; sourceTree = BUILT_PRODUCTS_DIR;')
source_phase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
script_phase = obj('engine', 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; alwaysOutOfDate = 1; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = "bash \\\"$SRCROOT/Tools/build-engine.sh\\\"";')
configs = []
for name in ['Debug', 'Release']:
    settings = {
        'PRODUCT_NAME': 'Silverphase', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.silverphase.editor',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'Silverphase',
        'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0',
        'TARGETED_DEVICE_FAMILY': '1,2', 'ARCHS': 'arm64', 'SWIFT_VERSION': '6.0',
        'SWIFT_STRICT_CONCURRENCY': 'complete', 'SWIFT_OBJC_BRIDGING_HEADER': '$(SRCROOT)/Sources/EngineBridge.h',
        'HEADER_SEARCH_PATHS': '$(SRCROOT)/../../engine/include', 'INFOPLIST_FILE': 'Info.plist',
        'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_ENTITLEMENTS': 'Silverphase.entitlements', 'ENABLE_USER_SCRIPT_SANDBOXING': 'NO',
        'OTHER_LDFLAGS': '$(DERIVED_FILE_DIR)/libSilverphaseEngine.a -lc++ -framework Metal -framework Foundation -framework QuartzCore -framework Accelerate -framework CoreText -framework CoreGraphics',
        'CLANG_MODULE_CACHE_PATH': '$(DERIVED_FILE_DIR)/module-cache',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
        'ALWAYS_SEARCH_USER_PATHS': 'NO', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'SILVERPHASE_APP DEBUG' if name == 'Debug' else 'SILVERPHASE_APP',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym', 'GENERATE_INFOPLIST_FILE': 'NO',
    }
    configs.append(obj('config:' + name, 'isa = XCBuildConfiguration; name = ' + name + '; buildSettings = {' + ''.join(k + ' = ' + quote(v) + ';' for k,v in settings.items()) + '};'))
config_list = obj('configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
app_info = plistlib.loads((root / 'Info.plist').read_bytes())
extension_targets, extension_dependencies, extension_phases = [], [], []
for name, suffix, extra_sources, extensionkit in [
    ('CameraControl', 'camera-control', [], False),
    ('LockedCamera', 'locked-camera', ['MobileCameraCanvas', 'MobileCameraCapturePose', 'MobileCaptureLocation', 'MobileCamera', 'MobileCameraCapture', 'MobileCameraChrome', 'MobileDevelopment', 'MobileFailure', 'EditorDesign'], True),
]:
    entry = f'CameraExtensions/{name}.swift'
    ref = obj(entry, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(entry)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    extension_builds = [obj('build:' + entry, f'isa = PBXBuildFile; fileRef = {ref};')]
    for source in ['SilverphaseCameraCaptureIntent', 'MobileCameraRecipe'] + extra_sources:
        ref = uid(f'Sources/{source}.swift')
        extension_builds.append(obj(f'{name}:build:{source}', f'isa = PBXBuildFile; fileRef = {ref};'))
    extension_resource_phases = []
    if extensionkit:
        catalog_source = os.path.relpath(shared / 'StockCatalogCore.swift', root)
        extension_builds.append(obj(f'{name}:build:StockCatalogCore', f'isa = PBXBuildFile; fileRef = {uid(catalog_source)};'))
        catalog_path = os.path.relpath(shared.parent / 'Resources/StockCatalog.json', root)
        catalog_ref = obj(name + ':catalog-ref', f'isa = PBXFileReference; lastKnownFileType = text.json; path = {quote(catalog_path)}; sourceTree = SOURCE_ROOT;')
        refs.append(catalog_ref)
        catalog_build = obj(name + ':catalog-build', f'isa = PBXBuildFile; fileRef = {catalog_ref};')
        extension_resource_phases.append(obj(name + ':catalog-copy', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = AppResources; dstSubfolderSpec = 7; files = ({catalog_build}); runOnlyForDeploymentPostprocessing = 0;'))
        for shader in [root / 'Shaders/MobileView.metal', repo / 'modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal']:
            path = os.path.relpath(shader, root)
            ref = obj(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.metal; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
            refs.append(ref)
            extension_builds.append(obj(f'{name}:build:{path}', f'isa = PBXBuildFile; fileRef = {ref};'))
    phase = obj(name + ':sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(extension_builds)}); runOnlyForDeploymentPostprocessing = 0;')
    extension_type = 'extensionkit-extension' if extensionkit else 'app-extension'
    file_type = 'wrapper.extensionkit-extension' if extensionkit else 'wrapper.app-extension'
    extension_product = obj(name + ':product', f'isa = PBXFileReference; explicitFileType = {file_type}; path = {name}.appex; sourceTree = BUILT_PRODUCTS_DIR;')
    refs.append(extension_product)
    settings = {
        'PRODUCT_NAME': name, 'PRODUCT_BUNDLE_IDENTIFIER': 'com.silverphase.editor.' + suffix,
        'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'TARGETED_DEVICE_FAMILY': '1,2', 'ARCHS': 'arm64',
        'SWIFT_VERSION': '6.0', 'CODE_SIGN_STYLE': 'Automatic', 'SKIP_INSTALL': 'YES',
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'GENERATE_INFOPLIST_FILE': 'YES', 'ALWAYS_SEARCH_USER_PATHS': 'NO',
        'INFOPLIST_FILE': f'CameraExtensions/{name}-Info.plist',
        'INFOPLIST_KEY_CFBundleDisplayName': 'Silverphase',
        'MARKETING_VERSION': app_info['CFBundleShortVersionString'], 'CURRENT_PROJECT_VERSION': app_info['CFBundleVersion'],
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    }
    if extensionkit:
        settings['INFOPLIST_KEY_NSCameraUsageDescription'] = app_info['NSCameraUsageDescription']
        settings['MTL_COMPILER_FLAGS'] = '-DSILVERPHASE_LOCKED_CAMERA -fmetal-math-mode=safe -fmetal-math-fp32-functions=precise'
    extension_configs = [obj(f'{name}:config:{configuration}', f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{' +
                             ''.join(k + ' = ' + quote(v) + ';' for k, v in settings.items()) + '};')
                         for configuration in ['Debug', 'Release']]
    extension_config_list = obj(name + ':configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(extension_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    extension_target = obj(name + ':target', f'isa = PBXNativeTarget; name = {name}; productName = {name}; productReference = {extension_product}; productType = "com.apple.product-type.{extension_type}"; buildConfigurationList = {extension_config_list}; buildPhases = ({",".join([phase] + extension_resource_phases)}); buildRules = (); dependencies = ();')
    extension_targets.append(extension_target)
    proxy = obj(name + ':proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {extension_target}; remoteInfo = {name};')
    extension_dependencies.append(obj(name + ':dependency', f'isa = PBXTargetDependency; target = {extension_target}; targetProxy = {proxy};'))
    embedded = obj(name + ':embedded', f'isa = PBXBuildFile; fileRef = {extension_product}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};')
    destination, path = (16, '$(EXTENSIONS_FOLDER_PATH)') if extensionkit else (13, '')
    extension_phases.append(obj(name + ':embed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = {quote(path)}; dstSubfolderSpec = {destination}; files = ({embedded}); runOnlyForDeploymentPostprocessing = 0;'))
group = obj('group', f'isa = PBXGroup; children = ({",".join(refs + [product, uid("uitest-source"), uid("uitest-product")])}); sourceTree = "<group>";')
target = obj('target', f'isa = PBXNativeTarget; name = Silverphase; productName = Silverphase; productReference = {product}; productType = "com.apple.product-type.application"; buildConfigurationList = {config_list}; buildPhases = ({script_phase},{source_phase},{resource_phase},{",".join(extension_phases)}); buildRules = (); dependencies = ({",".join(extension_dependencies)});')
test_ref = obj('uitest-source', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/PhotoImportTests.swift; sourceTree = SOURCE_ROOT;')
test_build = obj('uitest-build', f'isa = PBXBuildFile; fileRef = {test_ref};')
test_product = obj('uitest-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SilverphaseUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
test_sources = obj('uitest-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({test_build}); runOnlyForDeploymentPostprocessing = 0;')
test_config_ids = []
for name in ['Debug', 'Release']:
    settings = {
        'PRODUCT_NAME': 'SilverphaseUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.silverphase.editor.uitests',
        'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'TARGETED_DEVICE_FAMILY': '1,2', 'ARCHS': 'arm64',
        'SWIFT_VERSION': '6.0', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'Silverphase',
        'CODE_SIGN_STYLE': 'Automatic', 'ALWAYS_SEARCH_USER_PATHS': 'NO',
    }
    test_config_ids.append(obj('uitest-config:' + name, 'isa = XCBuildConfiguration; name = ' + name + '; buildSettings = {' + ''.join(k + ' = ' + quote(v) + ';' for k,v in settings.items()) + '};'))
test_configs = obj('uitest-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(test_config_ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
proxy = obj('uitest-proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Silverphase;')
dependency = obj('uitest-dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
test_target = obj('uitest-target', f'isa = PBXNativeTarget; name = SilverphaseUITests; productName = SilverphaseUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = {test_configs}; buildPhases = ({test_sources}); buildRules = (); dependencies = ({dependency});')
project_config_ids = [obj('project-config:' + name, 'isa = XCBuildConfiguration; name = ' + name + '; buildSettings = {};') for name in ['Debug', 'Release']]
project_configs = obj('project-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_config_ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project = obj('project', f'isa = PBXProject; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (zh_CN,en,Base); mainGroup = {group}; projectDirPath = ""; projectRoot = ""; targets = ({target},{test_target},{",".join(extension_targets)}); attributes = {{LastUpgradeCheck = 2710; TargetAttributes = {{{target} = {{SystemCapabilities = {{com.apple.IncreasedMemoryLimit = {{enabled = 1;}};}};}};}};}};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n'
dest = root / 'Silverphase.xcodeproj/project.pbxproj'
if '--check' in sys.argv:
    if not dest.exists() or dest.read_text() != text: sys.exit('iOS project needs regeneration')
else:
    dest.parent.mkdir(parents=True, exist_ok=True); dest.write_text(text)

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Silverphase.app" BlueprintName="Silverphase" ReferencedContainer="container:Silverphase.xcodeproj"/></BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="SilverphaseUITests.xctest" BlueprintName="SilverphaseUITests" ReferencedContainer="container:Silverphase.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="SilverphaseUITests.xctest" BlueprintName="SilverphaseUITests" ReferencedContainer="container:Silverphase.xcodeproj"/></TestableReference></Testables></TestAction>
</Scheme>
'''
scheme_path = root / 'Silverphase.xcodeproj/xcshareddata/xcschemes/SilverphaseUITests.xcscheme'
if '--check' in sys.argv:
    if not scheme_path.exists() or scheme_path.read_text() != scheme: sys.exit('iOS UI test scheme needs regeneration')
else:
    scheme_path.parent.mkdir(parents=True, exist_ok=True); scheme_path.write_text(scheme)

app_scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Silverphase.app" BlueprintName="Silverphase" ReferencedContainer="container:Silverphase.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Silverphase.app" BlueprintName="Silverphase" ReferencedContainer="container:Silverphase.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Silverphase.app" BlueprintName="Silverphase" ReferencedContainer="container:Silverphase.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
app_scheme_path = scheme_path.with_name('Silverphase.xcscheme')
if '--check' in sys.argv:
    if not app_scheme_path.exists() or app_scheme_path.read_text() != app_scheme: sys.exit('iOS app scheme needs regeneration')
else:
    app_scheme_path.write_text(app_scheme)
