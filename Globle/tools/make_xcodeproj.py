#!/usr/bin/env python3
"""Generate Globle.xcodeproj by scanning the source tree.

Doing this programmatically guarantees every UUID cross-reference is consistent
(the usual failure mode when hand-writing a .pbxproj). Re-run any time you add files:

    python3 tools/make_xcodeproj.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(HERE, ".."))
APP_NAME = "Globle"
SOURCE_DIR = os.path.join(PROJECT_DIR, APP_NAME)
BUNDLE_ID = "com.example.globle"
DEPLOYMENT_TARGET = "16.0"

_counter = [0]
def uid():
    _counter[0] += 1
    return f"{_counter[0]:024X}"

file_refs = []      # dicts: id, name, ftype, sourceTree, extra
groups = []         # dicts: id, name(optional), path(optional), sourceTree, children(list of ids), comment
source_refs = []    # (fr_id, name)
resource_refs = []  # (fr_id, name)


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
        source_refs.append((fr_id, name))
    elif role == "resource":
        resource_refs.append((fr_id, name))
    return fr_id


def build_group(dir_path, group_name):
    gid = uid()
    children = []
    for entry in sorted(os.listdir(dir_path)):
        if entry.startswith("."):
            continue
        full = os.path.join(dir_path, entry)
        if os.path.isdir(full) and not entry.endswith(".xcassets"):
            child = build_group(full, entry)
            children.append(child)
        else:
            children.append(make_file_ref(entry))
    groups.append({"id": gid, "path": group_name, "sourceTree": '"<group>"',
                   "children": children, "comment": group_name})
    return gid


def section(name, lines):
    if not lines:
        return ""
    body = "\n".join(lines)
    return f"\n/* Begin {name} section */\n{body}\n/* End {name} section */\n"


def main():
    # Build the source group tree.
    app_group_id = build_group(SOURCE_DIR, APP_NAME)

    product_id = uid()
    products_group_id = uid()
    main_group_id = uid()
    target_id = uid()
    project_id = uid()
    sources_phase_id = uid()
    frameworks_phase_id = uid()
    resources_phase_id = uid()
    target_cfg_list_id = uid()
    project_cfg_list_id = uid()
    proj_debug_id, proj_release_id = uid(), uid()
    tgt_debug_id, tgt_release_id = uid(), uid()

    # Products group + main group.
    groups.append({"id": products_group_id, "name": "Products", "sourceTree": '"<group>"',
                   "children": [product_id], "comment": "Products"})
    groups.append({"id": main_group_id, "sourceTree": '"<group>"',
                   "children": [app_group_id, products_group_id], "comment": None})

    # Build files.
    source_build = [(uid(), fr, name) for fr, name in source_refs]
    resource_build = [(uid(), fr, name) for fr, name in resource_refs]

    L = []
    L.append("// !$*UTF8*$!")
    L.append("{")
    L.append("\tarchiveVersion = 1;")
    L.append("\tclasses = {")
    L.append("\t};")
    L.append("\tobjectVersion = 56;")
    L.append("\tobjects = {")

    # PBXBuildFile
    bf_lines = []
    for bf, fr, name in source_build:
        bf_lines.append(f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};")
    for bf, fr, name in resource_build:
        bf_lines.append(f"\t\t{bf} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};")
    L.append(section("PBXBuildFile", bf_lines))

    # PBXFileReference
    fr_lines = []
    for f in file_refs:
        fr_lines.append(
            f"\t\t{f['id']} /* {f['name']} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {f['ftype']}; path = \"{f['name']}\"; sourceTree = {f['sourceTree']}; }};")
    fr_lines.append(
        f"\t\t{product_id} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L.append(section("PBXFileReference", fr_lines))

    # PBXFrameworksBuildPhase
    fw = [f"\t\t{frameworks_phase_id} /* Frameworks */ = {{",
          "\t\t\tisa = PBXFrameworksBuildPhase;",
          "\t\t\tbuildActionMask = 2147483647;",
          "\t\t\tfiles = (",
          "\t\t\t);",
          "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
          "\t\t};"]
    L.append(section("PBXFrameworksBuildPhase", fw))

    # PBXGroup
    g_lines = []
    for g in groups:
        g_lines.append(f"\t\t{g['id']}" + (f" /* {g['comment']} */" if g.get("comment") else "") + " = {")
        g_lines.append("\t\t\tisa = PBXGroup;")
        g_lines.append("\t\t\tchildren = (")
        for c in g["children"]:
            name = next((f["name"] for f in file_refs if f["id"] == c), None)
            if name is None:
                name = next((gr.get("comment") or gr.get("name") or gr.get("path")
                             for gr in groups if gr["id"] == c), None)
            if c == product_id:
                name = f"{APP_NAME}.app"
            g_lines.append(f"\t\t\t\t{c}" + (f" /* {name} */" if name else "") + ",")
        g_lines.append("\t\t\t);")
        if g.get("name"):
            g_lines.append(f"\t\t\tname = {g['name']};")
        if g.get("path"):
            g_lines.append(f"\t\t\tpath = {g['path']};")
        g_lines.append(f"\t\t\tsourceTree = {g['sourceTree']};")
        g_lines.append("\t\t};")
    L.append(section("PBXGroup", g_lines))

    # PBXNativeTarget
    nt = [f"\t\t{target_id} /* {APP_NAME} */ = {{",
          "\t\t\tisa = PBXNativeTarget;",
          f"\t\t\tbuildConfigurationList = {target_cfg_list_id} /* Build configuration list for PBXNativeTarget \"{APP_NAME}\" */;",
          "\t\t\tbuildPhases = (",
          f"\t\t\t\t{sources_phase_id} /* Sources */,",
          f"\t\t\t\t{frameworks_phase_id} /* Frameworks */,",
          f"\t\t\t\t{resources_phase_id} /* Resources */,",
          "\t\t\t);",
          "\t\t\tbuildRules = (",
          "\t\t\t);",
          "\t\t\tdependencies = (",
          "\t\t\t);",
          f"\t\t\tname = {APP_NAME};",
          f"\t\t\tproductName = {APP_NAME};",
          f"\t\t\tproductReference = {product_id} /* {APP_NAME}.app */;",
          "\t\t\tproductType = \"com.apple.product-type.application\";",
          "\t\t};"]
    L.append(section("PBXNativeTarget", nt))

    # PBXProject
    pj = [f"\t\t{project_id} /* Project object */ = {{",
          "\t\t\tisa = PBXProject;",
          "\t\t\tattributes = {",
          "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
          "\t\t\t\tLastSwiftUpdateCheck = 1520;",
          "\t\t\t\tLastUpgradeCheck = 1520;",
          "\t\t\t\tTargetAttributes = {",
          f"\t\t\t\t\t{target_id} = {{",
          "\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;",
          "\t\t\t\t\t};",
          "\t\t\t\t};",
          "\t\t\t};",
          f"\t\t\tbuildConfigurationList = {project_cfg_list_id} /* Build configuration list for PBXProject \"{APP_NAME}\" */;",
          "\t\t\tcompatibilityVersion = \"Xcode 14.0\";",
          "\t\t\tdevelopmentRegion = en;",
          "\t\t\thasScannedForEncodings = 0;",
          "\t\t\tknownRegions = (",
          "\t\t\t\ten,",
          "\t\t\t\tBase,",
          "\t\t\t);",
          f"\t\t\tmainGroup = {main_group_id};",
          f"\t\t\tproductRefGroup = {products_group_id} /* Products */;",
          "\t\t\tprojectDirPath = \"\";",
          "\t\t\tprojectRoot = \"\";",
          "\t\t\ttargets = (",
          f"\t\t\t\t{target_id} /* {APP_NAME} */,",
          "\t\t\t);",
          "\t\t};"]
    L.append(section("PBXProject", pj))

    # PBXResourcesBuildPhase
    rb = [f"\t\t{resources_phase_id} /* Resources */ = {{",
          "\t\t\tisa = PBXResourcesBuildPhase;",
          "\t\t\tbuildActionMask = 2147483647;",
          "\t\t\tfiles = ("]
    for bf, fr, name in resource_build:
        rb.append(f"\t\t\t\t{bf} /* {name} in Resources */,")
    rb += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    L.append(section("PBXResourcesBuildPhase", rb))

    # PBXSourcesBuildPhase
    sb = [f"\t\t{sources_phase_id} /* Sources */ = {{",
          "\t\t\tisa = PBXSourcesBuildPhase;",
          "\t\t\tbuildActionMask = 2147483647;",
          "\t\t\tfiles = ("]
    for bf, fr, name in source_build:
        sb.append(f"\t\t\t\t{bf} /* {name} in Sources */,")
    sb += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    L.append(section("PBXSourcesBuildPhase", sb))

    # XCBuildConfiguration
    L.append(section("XCBuildConfiguration", [
        build_config(proj_debug_id, "Debug", project_settings("Debug")),
        build_config(proj_release_id, "Release", project_settings("Release")),
        build_config(tgt_debug_id, "Debug", target_settings()),
        build_config(tgt_release_id, "Release", target_settings()),
    ]))

    # XCConfigurationList
    cfg_lists = [
        config_list(project_cfg_list_id, f"PBXProject \"{APP_NAME}\"", proj_debug_id, proj_release_id),
        config_list(target_cfg_list_id, f"PBXNativeTarget \"{APP_NAME}\"", tgt_debug_id, tgt_release_id),
    ]
    L.append(section("XCConfigurationList", cfg_lists))

    L.append("\t};")
    L.append(f"\trootObject = {project_id} /* Project object */;")
    L.append("}")

    proj_path = os.path.join(PROJECT_DIR, f"{APP_NAME}.xcodeproj")
    os.makedirs(os.path.join(proj_path, "project.xcworkspace"), exist_ok=True)
    with open(os.path.join(proj_path, "project.pbxproj"), "w") as f:
        f.write("\n".join(line for line in L if line is not None) + "\n")
    with open(os.path.join(proj_path, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
                '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

    scheme_dir = os.path.join(proj_path, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, f"{APP_NAME}.xcscheme"), "w") as f:
        f.write(scheme_xml(target_id))

    print(f"Wrote {proj_path}")
    print(f"  {len(source_build)} source files, {len(resource_build)} resources, {len(groups)} groups")
    print(f"  shared scheme: {APP_NAME}.xcscheme")


def scheme_xml(target_id):
    ref = (f'            BuildableIdentifier = "primary"\n'
           f'            BlueprintIdentifier = "{target_id}"\n'
           f'            BuildableName = "{APP_NAME}.app"\n'
           f'            BlueprintName = "{APP_NAME}"\n'
           f'            ReferencedContainer = "container:{APP_NAME}.xcodeproj"')
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
{ref}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
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
{ref}>
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
{ref}>
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


def build_config(cid, name, settings):
    lines = [f"\t\t{cid} /* {name} */ = {{", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    for k in sorted(settings):
        lines.append(f"\t\t\t\t{k} = {settings[k]};")
    lines += ["\t\t\t};", f"\t\t\tname = {name};", "\t\t};"]
    return "\n".join(lines)


def config_list(clid, owner, debug_id, release_id):
    return "\n".join([
        f"\t\t{clid} /* Build configuration list for {owner} */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{debug_id} /* Debug */,",
        f"\t\t\t\t{release_id} /* Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t};",
    ])


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
        s.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        })
    else:
        s.update({
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
            "VALIDATE_PRODUCT": "YES",
        })
    return s


def target_settings():
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


if __name__ == "__main__":
    main()
