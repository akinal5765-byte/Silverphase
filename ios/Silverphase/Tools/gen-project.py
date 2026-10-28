#!/usr/bin/env python3
"""Generate the iOS project; all shared references stay relative to the repo."""
from pathlib import Path
import hashlib
import os
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
resource_phase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({icon_build}); runOnlyForDeploymentPostprocessing = 0;')
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Silverphase.app; sourceTree = BUILT_PRODUCTS_DIR;')
group = obj('group', f'isa = PBXGroup; children = ({",".join(refs + [product, uid("uitest-source"), uid("uitest-product")])}); sourceTree = "<group>";')
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
        'ALWAYS_SEARCH_USER_PATHS': 'NO', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if name == 'Debug' else '',
        'DEBUG_INFORMATION_FORMAT': 'dwarf', 'GENERATE_INFOPLIST_FILE': 'NO',
    }
    configs.append(obj('config:' + name, 'isa = XCBuildConfiguration; name = ' + name + '; buildSettings = {' + ''.join(k + ' = ' + quote(v) + ';' for k,v in settings.items()) + '};'))
config_list = obj('configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; name = Silverphase; productName = Silverphase; productReference = {product}; productType = "com.apple.product-type.application"; buildConfigurationList = {config_list}; buildPhases = ({script_phase},{source_phase},{resource_phase}); buildRules = (); dependencies = ();')
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
project = obj('project', f'isa = PBXProject; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (zh_CN,en,Base); mainGroup = {group}; projectDirPath = ""; projectRoot = ""; targets = ({target},{test_target}); attributes = {{LastUpgradeCheck = 2710; TargetAttributes = {{{target} = {{SystemCapabilities = {{com.apple.IncreasedMemoryLimit = {{enabled = 1;}};}};}};}};}};')
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
