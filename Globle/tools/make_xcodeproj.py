#!/usr/bin/env python3
"""Generate Globle.xcodeproj by scanning the source tree.

Doing this programmatically guarantees every UUID cross-reference is consistent
(the usual failure mode when hand-writing a .pbxproj). It builds the app target
from Globle/ and, if a GlobleTests/ folder exists, a unit-test target too.
Re-run any time you add files:

    python3 tools/make_xcodeproj.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(HERE, ".."))
APP_NAME = "Globle"
TEST_NAME = "GlobleTests"
SOURCE_DIR = os.path.join(PROJECT_DIR, APP_NAME)
TEST_DIR = os.path.join(PROJECT_DIR, TEST_NAME)
BUNDLE_ID = "com.example.globle"
DEPLOYMENT_TARGET = "16.0"

_counter = [0]
def uid():
    _counter[0] += 1
    return f"{_counter[0]:024X}"

file_refs = []        # dicts: id, name, ftype, sourceTree
groups = []           # dicts: id, name?, path?, sourceTree, children, comment
app_sources = []      # (fr_id, name)
app_resources = []    # (fr_id, name)
test_sources = []     # (fr_id, name)
_collect = "app"


def file_type(name):
    if name.endswith(".xcassets"):
        return "folder.assetcatalog", "resource"
    ext = os.path.splitext(name)[1].lower()
    return {
        ".swift": ("sourcecode.swift", "source"),
        ".json": ("text.json", "resource"),
        ".plist": ("text.plist.xml", "none"),
        ".md": ("net.daringfireball.markdown", "none"),
        ".png": ("image.png", "none"),
    }.get(ext, ("text", "none"))


def make_file_ref(name):
    ftype, role = file_type(name)
    fr_id = uid()
    file_refs.append({"id": fr_id, "name": name, "ftype": ftype, "sourceTree": '"<group>"'})
    if role == "source":
        (app_sources if _collect == "app" else test_sources).append((fr_id, name))
    elif role == "resource" and _collect == "app":
        app_resources.append((fr_id, name))
    return fr_id


def build_group(dir_path, group_name):
    gid = uid()
    children = []
    for entry in sorted(os.listdir(dir_path)):
        if entry.startswith("."):
            continue
        full = os.path.join(dir_path, entry)
        if os.path.isdir(full) and not entry.endswith(".xcassets"):
            children.append(build_group(full, entry))
        else:
            children.append(make_file_ref(entry))
    groups.append({"id": gid, "path": group_name, "sourceTree": '"<group>"',
                   "children": children, "comment": group_name})
    return gid


def section(name, lines):
    if not lines:
        return ""
    return f"\n/* Begin {name} section */\n" + "\n".join(lines) + f"\n/* End {name} section */\n"


def main():
    global _collect
    _collect = "app"
    app_group_id = build_group(SOURCE_DIR, APP_NAME)

    has_tests = os.path.isdir(TEST_DIR) and any(f.endswith(".swift") for f in os.listdir(TEST_DIR))
    test_group_id = None
    if has_tests:
        _collect = "test"
        test_group_id = build_group(TEST_DIR, TEST_NAME)

    # Identifiers
    app_product = uid(); products_group = uid(); main_group = uid()
    app_target = uid(); project_id = uid()
    app_sources_phase = uid(); app_frameworks_phase = uid(); app_resources_phase = uid()
    proj_cfg_list = uid(); app_cfg_list = uid()
    proj_debug, proj_release = uid(), uid()
    app_debug, app_release = uid(), uid()

    if has_tests:
        test_product = uid(); test_target = uid()
        test_sources_phase = uid(); test_frameworks_phase = uid(); test_resources_phase = uid()
        test_cfg_list = uid(); test_debug, test_release = uid(), uid()
        dep_id = uid(); proxy_id = uid()

    product_names = {app_product: f"{APP_NAME}.app"}
    if has_tests:
        product_names[test_product] = f"{TEST_NAME}.xctest"

    app_src_build = [(uid(), fr, name) for fr, name in app_sources]
    app_res_build = [(uid(), fr, name) for fr, name in app_resources]
    test_src_build = [(uid(), fr, name) for fr, name in test_sources] if has_tests else []

    def name_for(obj_id):
        if obj_id in product_names:
            return product_names[obj_id]
        for f in file_refs:
            if f["id"] == obj_id:
                return f["name"]
        for g in groups:
            if g["id"] == obj_id:
                return g.get("comment") or g.get("name") or g.get("path")
        return None

    L = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
         "\tobjectVersion = 56;", "\tobjects = {"]

    # PBXBuildFile
    bf = []
    for b, fr, name in app_src_build:
        bf.append(f"\t\t{b} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};")
    for b, fr, name in app_res_build:
        bf.append(f"\t\t{b} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};")
    for b, fr, name in test_src_build:
        bf.append(f"\t\t{b} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};")
    L.append(section("PBXBuildFile", bf))

    # PBXContainerItemProxy
    if has_tests:
        L.append(section("PBXContainerItemProxy", [
            f"\t\t{proxy_id} /* PBXContainerItemProxy */ = {{",
            "\t\t\tisa = PBXContainerItemProxy;",
            f"\t\t\tcontainerPortal = {project_id} /* Project object */;",
            "\t\t\tproxyType = 1;",
            f"\t\t\tremoteGlobalIDString = {app_target};",
            f"\t\t\tremoteInfo = {APP_NAME};",
            "\t\t};"]))

    # PBXFileReference
    fr_lines = []
    for f in file_refs:
        fr_lines.append(
            f"\t\t{f['id']} /* {f['name']} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {f['ftype']}; path = \"{f['name']}\"; sourceTree = {f['sourceTree']}; }};")
    fr_lines.append(
        f"\t\t{app_product} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    if has_tests:
        fr_lines.append(
            f"\t\t{test_product} /* {TEST_NAME}.xctest */ = {{isa = PBXFileReference; explicitFileType = "
            f"wrapper.cfbundle; includeInIndex = 0; path = {TEST_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L.append(section("PBXFileReference", fr_lines))

    # PBXFrameworksBuildPhase
    fw = empty_phase(app_frameworks_phase, "Frameworks", "PBXFrameworksBuildPhase")
    if has_tests:
        fw += "\n" + empty_phase(test_frameworks_phase, "Frameworks", "PBXFrameworksBuildPhase")
    L.append(section("PBXFrameworksBuildPhase", [fw]))

    # PBXGroup
    products_children = [app_product] + ([test_product] if has_tests else [])
    groups.append({"id": products_group, "name": "Products", "sourceTree": '"<group>"',
                   "children": products_children, "comment": "Products"})
    main_children = [app_group_id] + ([test_group_id] if has_tests else []) + [products_group]
    groups.append({"id": main_group, "sourceTree": '"<group>"', "children": main_children, "comment": None})

    g_lines = []
    for g in groups:
        g_lines.append(f"\t\t{g['id']}" + (f" /* {g['comment']} */" if g.get("comment") else "") + " = {")
        g_lines.append("\t\t\tisa = PBXGroup;")
        g_lines.append("\t\t\tchildren = (")
        for c in g["children"]:
            nm = name_for(c)
            g_lines.append(f"\t\t\t\t{c}" + (f" /* {nm} */" if nm else "") + ",")
        g_lines.append("\t\t\t);")
        if g.get("name"):
            g_lines.append(f"\t\t\tname = {g['name']};")
        if g.get("path"):
            g_lines.append(f"\t\t\tpath = {g['path']};")
        g_lines.append(f"\t\t\tsourceTree = {g['sourceTree']};")
        g_lines.append("\t\t};")
    L.append(section("PBXGroup", g_lines))

    # PBXNativeTarget
    nt = native_target(app_target, APP_NAME, app_cfg_list,
                       [app_sources_phase, app_frameworks_phase, app_resources_phase],
                       app_product, f"{APP_NAME}.app", "com.apple.product-type.application", deps=[])
    if has_tests:
        nt += "\n" + native_target(
            test_target, TEST_NAME, test_cfg_list,
            [test_sources_phase, test_frameworks_phase, test_resources_phase],
            test_product, f"{TEST_NAME}.xctest", "com.apple.product-type.bundle.unit-test",
            deps=[(dep_id, "PBXTargetDependency")])
    L.append(section("PBXNativeTarget", [nt]))

    # PBXProject
    target_attrs = [f"\t\t\t\t\t{app_target} = {{", "\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;", "\t\t\t\t\t};"]
    if has_tests:
        target_attrs += [f"\t\t\t\t\t{test_target} = {{", "\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;",
                         f"\t\t\t\t\t\tTestTargetID = {app_target};", "\t\t\t\t\t};"]
    targets_list = [f"\t\t\t\t{app_target} /* {APP_NAME} */,"]
    if has_tests:
        targets_list.append(f"\t\t\t\t{test_target} /* {TEST_NAME} */,")
    pj = [f"\t\t{project_id} /* Project object */ = {{", "\t\t\tisa = PBXProject;", "\t\t\tattributes = {",
          "\t\t\t\tBuildIndependentTargetsInParallel = 1;", "\t\t\t\tLastSwiftUpdateCheck = 1520;",
          "\t\t\t\tLastUpgradeCheck = 1520;", "\t\t\t\tTargetAttributes = {"] + target_attrs + \
         ["\t\t\t\t};", "\t\t\t};",
          f"\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject \"{APP_NAME}\" */;",
          "\t\t\tcompatibilityVersion = \"Xcode 14.0\";", "\t\t\tdevelopmentRegion = en;",
          "\t\t\thasScannedForEncodings = 0;", "\t\t\tknownRegions = (", "\t\t\t\ten,", "\t\t\t\tBase,", "\t\t\t);",
          f"\t\t\tmainGroup = {main_group};", f"\t\t\tproductRefGroup = {products_group} /* Products */;",
          "\t\t\tprojectDirPath = \"\";", "\t\t\tprojectRoot = \"\";", "\t\t\ttargets = ("] + targets_list + \
         ["\t\t\t);", "\t\t};"]
    L.append(section("PBXProject", pj))

    # PBXResourcesBuildPhase
    rb = files_phase(app_resources_phase, "Resources", "PBXResourcesBuildPhase",
                     [(b, name, "Resources") for b, _, name in app_res_build])
    if has_tests:
        rb += "\n" + empty_phase(test_resources_phase, "Resources", "PBXResourcesBuildPhase")
    L.append(section("PBXResourcesBuildPhase", [rb]))

    # PBXSourcesBuildPhase
    sb = files_phase(app_sources_phase, "Sources", "PBXSourcesBuildPhase",
                     [(b, name, "Sources") for b, _, name in app_src_build])
    if has_tests:
        sb += "\n" + files_phase(test_sources_phase, "Sources", "PBXSourcesBuildPhase",
                                 [(b, name, "Sources") for b, _, name in test_src_build])
    L.append(section("PBXSourcesBuildPhase", [sb]))

    # PBXTargetDependency
    if has_tests:
        L.append(section("PBXTargetDependency", [
            f"\t\t{dep_id} /* PBXTargetDependency */ = {{",
            "\t\t\tisa = PBXTargetDependency;",
            f"\t\t\ttarget = {app_target} /* {APP_NAME} */;",
            f"\t\t\ttargetProxy = {proxy_id} /* PBXContainerItemProxy */;",
            "\t\t};"]))

    # XCBuildConfiguration
    cfgs = [build_config(proj_debug, "Debug", project_settings("Debug")),
            build_config(proj_release, "Release", project_settings("Release")),
            build_config(app_debug, "Debug", app_settings()),
            build_config(app_release, "Release", app_settings())]
    if has_tests:
        cfgs += [build_config(test_debug, "Debug", test_settings()),
                 build_config(test_release, "Release", test_settings())]
    L.append(section("XCBuildConfiguration", cfgs))

    # XCConfigurationList
    lists = [config_list(proj_cfg_list, f"PBXProject \"{APP_NAME}\"", proj_debug, proj_release),
             config_list(app_cfg_list, f"PBXNativeTarget \"{APP_NAME}\"", app_debug, app_release)]
    if has_tests:
        lists.append(config_list(test_cfg_list, f"PBXNativeTarget \"{TEST_NAME}\"", test_debug, test_release))
    L.append(section("XCConfigurationList", lists))

    L += ["\t};", f"\trootObject = {project_id} /* Project object */;", "}"]

    proj_path = os.path.join(PROJECT_DIR, f"{APP_NAME}.xcodeproj")
    os.makedirs(os.path.join(proj_path, "project.xcworkspace"), exist_ok=True)
    with open(os.path.join(proj_path, "project.pbxproj"), "w") as f:
        f.write("\n".join(L) + "\n")
    with open(os.path.join(proj_path, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
                '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

    scheme_dir = os.path.join(proj_path, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, f"{APP_NAME}.xcscheme"), "w") as f:
        f.write(scheme_xml(app_target, test_target if has_tests else None))

    print(f"Wrote {proj_path}")
    print(f"  app: {len(app_src_build)} sources, {len(app_res_build)} resources")
    if has_tests:
        print(f"  tests: {len(test_src_build)} sources (target {TEST_NAME})")
    print(f"  groups: {len(groups)}, shared scheme: {APP_NAME}.xcscheme")


def empty_phase(pid, name, isa):
    return "\n".join([f"\t\t{pid} /* {name} */ = {{", f"\t\t\tisa = {isa};",
                      "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = (", "\t\t\t);",
                      "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"])


def files_phase(pid, name, isa, entries):
    lines = [f"\t\t{pid} /* {name} */ = {{", f"\t\t\tisa = {isa};",
             "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    for b, fname, phase in entries:
        lines.append(f"\t\t\t\t{b} /* {fname} in {phase} */,")
    lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    return "\n".join(lines)


def native_target(tid, name, cfg_list, phases, product, product_name, ptype, deps):
    dep_lines = [f"\t\t\t\t{d} /* {comment} */," for d, comment in deps]
    return "\n".join([
        f"\t\t{tid} /* {name} */ = {{", "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {cfg_list} /* Build configuration list for PBXNativeTarget \"{name}\" */;",
        "\t\t\tbuildPhases = ("] +
        [f"\t\t\t\t{p} /* {label} */," for p, label in
         zip(phases, ["Sources", "Frameworks", "Resources"])] +
        ["\t\t\t);", "\t\t\tbuildRules = (", "\t\t\t);", "\t\t\tdependencies = ("] + dep_lines +
        ["\t\t\t);", f"\t\t\tname = {name};", f"\t\t\tproductName = {name};",
         f"\t\t\tproductReference = {product} /* {product_name} */;",
         f"\t\t\tproductType = \"{ptype}\";", "\t\t};"])


def build_config(cid, name, settings):
    lines = [f"\t\t{cid} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    for k in sorted(settings):
        lines.append(f"\t\t\t\t{k} = {settings[k]};")
    lines += ["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"]
    return "\n".join(lines)


def config_list(clid, owner, debug_id, release_id):
    return "\n".join([
        f"\t\t{clid} /* Build configuration list for {owner} */ = {{", "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (", f"\t\t\t\t{debug_id} /* Debug */,", f"\t\t\t\t{release_id} /* Release */,",
        "\t\t\t);", "\t\t\tdefaultConfigurationIsVisible = 0;", "\t\t\tdefaultConfigurationName = Release;", "\t\t};"])


def project_settings(config):
    s = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
    }
    if config == "Debug":
        s.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                  "GCC_DYNAMIC_NO_PIC": "NO", "GCC_OPTIMIZATION_LEVEL": "0",
                  "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
                  "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE", "ONLY_ACTIVE_ARCH": "YES",
                  "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
                  "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'})
    else:
        s.update({"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "ENABLE_NS_ASSERTIONS": "NO",
                  "MTL_ENABLE_DEBUG_INFO": "NO", "SWIFT_COMPILATION_MODE": "wholemodule",
                  "SWIFT_OPTIMIZATION_LEVEL": '"-O"', "VALIDATE_PRODUCT": "YES"})
    return s


def app_settings():
    return {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/Frameworks"',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }


def test_settings():
    return {
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_TESTING_SEARCH_PATHS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/Frameworks @loader_path/Frameworks"',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}Tests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP_NAME}"',
    }


def scheme_xml(app_target, test_target):
    def ref(tid, name, product):
        return (f'            BuildableIdentifier = "primary"\n'
                f'            BlueprintIdentifier = "{tid}"\n'
                f'            BuildableName = "{product}"\n'
                f'            BlueprintName = "{name}"\n'
                f'            ReferencedContainer = "container:{APP_NAME}.xcodeproj"')
    app_ref = ref(app_target, APP_NAME, f"{APP_NAME}.app")

    test_build_entry = ""
    testables = "      <Testables>\n      </Testables>"
    if test_target:
        test_ref = ref(test_target, TEST_NAME, f"{TEST_NAME}.xctest")
        test_build_entry = f'''         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
{test_ref}>
            </BuildableReference>
         </BuildActionEntry>
'''
        testables = f'''      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
{test_ref}>
            </BuildableReference>
         </TestableReference>
      </Testables>'''

    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
{app_ref}>
            </BuildableReference>
         </BuildActionEntry>
{test_build_entry}      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
{testables}
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
{app_ref}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
{app_ref}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''


if __name__ == "__main__":
    main()
