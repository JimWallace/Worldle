import Foundation

// Generate Globle.xcodeproj by scanning the source tree. Doing this programmatically
// guarantees every UUID cross-reference is consistent. Builds the app target from
// Globle/ and, if GlobleTests/ exists, a unit-test target too. Swift port of
// make_xcodeproj.py. Re-run after adding/removing files: `swift run make-xcodeproj`.

let appName = "Globle"
let testName = "GlobleTests"
let bundleId = "com.example.globle"
let deploymentTarget = "16.0"

func projectDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}
let proj = projectDir()
let sourceDir = proj.appendingPathComponent(appName)
let testDir = proj.appendingPathComponent(testName)

let fm = FileManager.default
var counter: UInt64 = 0
func uid() -> String { counter += 1; return String(format: "%024llX", counter) }

struct FileRef { let id, name, ftype: String }
struct Group { let id: String; var name: String?; var path: String?; let sourceTree: String; var children: [String]; var comment: String? }

var fileRefs: [FileRef] = []
var groups: [Group] = []
var appSources: [(String, String)] = []
var appResources: [(String, String)] = []
var testSources: [(String, String)] = []
var collect = "app"
var productNames: [String: String] = [:]

func fileType(_ name: String) -> (String, String) {
    if name.hasSuffix(".xcassets") { return ("folder.assetcatalog", "resource") }
    switch (name as NSString).pathExtension.lowercased() {
    case "swift": return ("sourcecode.swift", "source")
    case "json": return ("text.json", "resource")
    case "plist": return ("text.plist.xml", "none")
    case "md": return ("net.daringfireball.markdown", "none")
    case "png": return ("image.png", "none")
    default: return ("text", "none")
    }
}

func makeFileRef(_ name: String) -> String {
    let (ftype, role) = fileType(name)
    let id = uid()
    fileRefs.append(FileRef(id: id, name: name, ftype: ftype))
    if role == "source" {
        if collect == "app" { appSources.append((id, name)) } else { testSources.append((id, name)) }
    } else if role == "resource" && collect == "app" {
        appResources.append((id, name))
    }
    return id
}

func dirEntries(_ url: URL) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}
func isDir(_ url: URL) -> Bool {
    var b: ObjCBool = false
    fm.fileExists(atPath: url.path, isDirectory: &b)
    return b.boolValue
}

func buildGroup(_ dir: URL, _ groupName: String) -> String {
    let gid = uid()
    var children: [String] = []
    for entry in dirEntries(dir) where !entry.hasPrefix(".") {
        let full = dir.appendingPathComponent(entry)
        if isDir(full) && !entry.hasSuffix(".xcassets") {
            children.append(buildGroup(full, entry))
        } else {
            children.append(makeFileRef(entry))
        }
    }
    groups.append(Group(id: gid, name: nil, path: groupName, sourceTree: "\"<group>\"",
                        children: children, comment: groupName))
    return gid
}

func section(_ name: String, _ lines: [String]) -> String {
    lines.isEmpty ? "" : "\n/* Begin \(name) section */\n" + lines.joined(separator: "\n") + "\n/* End \(name) section */\n"
}

func nameFor(_ id: String) -> String? {
    if let n = productNames[id] { return n }
    if let f = fileRefs.first(where: { $0.id == id }) { return f.name }
    if let g = groups.first(where: { $0.id == id }) { return g.comment ?? g.name ?? g.path }
    return nil
}

func emptyPhase(_ pid: String, _ name: String, _ isa: String) -> String {
    ["\t\t\(pid) /* \(name) */ = {", "\t\t\tisa = \(isa);", "\t\t\tbuildActionMask = 2147483647;",
     "\t\t\tfiles = (", "\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"].joined(separator: "\n")
}

func filesPhase(_ pid: String, _ name: String, _ isa: String, _ entries: [(String, String)]) -> String {
    var lines = ["\t\t\(pid) /* \(name) */ = {", "\t\t\tisa = \(isa);",
                 "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    for (b, fname) in entries { lines.append("\t\t\t\t\(b) /* \(fname) in \(name) */,") }
    lines += ["\t\t\t);", "\t\t\trunOnlyForDeploymentPostprocessing = 0;", "\t\t};"]
    return lines.joined(separator: "\n")
}

func nativeTarget(_ tid: String, _ name: String, _ cfgList: String, _ phases: [String],
                  _ product: String, _ productName: String, _ ptype: String, deps: [(String, String)]) -> String {
    var lines = ["\t\t\(tid) /* \(name) */ = {", "\t\t\tisa = PBXNativeTarget;",
                 "\t\t\tbuildConfigurationList = \(cfgList) /* Build configuration list for PBXNativeTarget \"\(name)\" */;",
                 "\t\t\tbuildPhases = ("]
    for (p, label) in zip(phases, ["Sources", "Frameworks", "Resources"]) {
        lines.append("\t\t\t\t\(p) /* \(label) */,")
    }
    lines += ["\t\t\t);", "\t\t\tbuildRules = (", "\t\t\t);", "\t\t\tdependencies = ("]
    for (d, comment) in deps { lines.append("\t\t\t\t\(d) /* \(comment) */,") }
    lines += ["\t\t\t);", "\t\t\tname = \(name);", "\t\t\tproductName = \(name);",
              "\t\t\tproductReference = \(product) /* \(productName) */;",
              "\t\t\tproductType = \"\(ptype)\";", "\t\t};"]
    return lines.joined(separator: "\n")
}

func buildConfig(_ cid: String, _ name: String, _ settings: [String: String]) -> String {
    var lines = ["\t\t\(cid) /* \(name) */ = {", "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    for k in settings.keys.sorted() { lines.append("\t\t\t\t\(k) = \(settings[k]!);") }
    lines += ["\t\t\t};", "\t\t\tname = \(name);", "\t\t};"]
    return lines.joined(separator: "\n")
}

func configList(_ clid: String, _ owner: String, _ debugId: String, _ releaseId: String) -> String {
    ["\t\t\(clid) /* Build configuration list for \(owner) */ = {", "\t\t\tisa = XCConfigurationList;",
     "\t\t\tbuildConfigurations = (", "\t\t\t\t\(debugId) /* Debug */,", "\t\t\t\t\(releaseId) /* Release */,",
     "\t\t\t);", "\t\t\tdefaultConfigurationIsVisible = 0;", "\t\t\tdefaultConfigurationName = Release;", "\t\t};"]
        .joined(separator: "\n")
}

func projectSettings(_ config: String) -> [String: String] {
    var s: [String: String] = [
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": #""gnu++20""#,
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
        "IPHONEOS_DEPLOYMENT_TARGET": deploymentTarget,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
    ]
    if config == "Debug" {
        s["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        s["ENABLE_TESTABILITY"] = "YES"
        s["GCC_DYNAMIC_NO_PIC"] = "NO"
        s["GCC_OPTIMIZATION_LEVEL"] = "0"
        s["GCC_PREPROCESSOR_DEFINITIONS"] = #""DEBUG=1 $(inherited)""#
        s["MTL_ENABLE_DEBUG_INFO"] = "INCLUDE_SOURCE"
        s["ONLY_ACTIVE_ARCH"] = "YES"
        s["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = #""DEBUG $(inherited)""#
        s["SWIFT_OPTIMIZATION_LEVEL"] = #""-Onone""#
    } else {
        s["DEBUG_INFORMATION_FORMAT"] = #""dwarf-with-dsym""#
        s["ENABLE_NS_ASSERTIONS"] = "NO"
        s["MTL_ENABLE_DEBUG_INFO"] = "NO"
        s["SWIFT_COMPILATION_MODE"] = "wholemodule"
        s["SWIFT_OPTIMIZATION_LEVEL"] = #""-O""#
        s["VALIDATE_PRODUCT"] = "YES"
    }
    return s
}

func appSettings() -> [String: String] {
    [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": #""UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight""#,
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": #""UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight""#,
        "IPHONEOS_DEPLOYMENT_TARGET": deploymentTarget,
        "LD_RUNPATH_SEARCH_PATHS": #""@executable_path/Frameworks""#,
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": bundleId,
        "PRODUCT_NAME": #""$(TARGET_NAME)""#,
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": #""1,2""#,
    ]
}

func testSettings() -> [String: String] {
    [
        "BUNDLE_LOADER": #""$(TEST_HOST)""#,
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_TESTING_SEARCH_PATHS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": deploymentTarget,
        "LD_RUNPATH_SEARCH_PATHS": #""@executable_path/Frameworks @loader_path/Frameworks""#,
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "\(bundleId)Tests",
        "PRODUCT_NAME": #""$(TARGET_NAME)""#,
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": #""1,2""#,
        "TEST_HOST": #""$(BUILT_PRODUCTS_DIR)/Globle.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Globle""#,
    ]
}

func schemeXML(_ appTarget: String, _ testTarget: String?) -> String {
    func ref(_ tid: String, _ name: String, _ product: String) -> String {
        """
                    BuildableIdentifier = "primary"
                    BlueprintIdentifier = "\(tid)"
                    BuildableName = "\(product)"
                    BlueprintName = "\(name)"
                    ReferencedContainer = "container:\(appName).xcodeproj"
        """
    }
    let appRef = ref(appTarget, appName, "\(appName).app")
    var testBuildEntry = ""
    var testables = "      <Testables>\n      </Testables>"
    if let testTarget {
        let testRef = ref(testTarget, testName, "\(testName).xctest")
        testBuildEntry = """
                 <BuildActionEntry
                    buildForTesting = "YES"
                    buildForRunning = "NO"
                    buildForProfiling = "NO"
                    buildForArchiving = "NO"
                    buildForAnalyzing = "NO">
                    <BuildableReference
        \(testRef)>
                    </BuildableReference>
                 </BuildActionEntry>

        """
        testables = """
              <Testables>
                 <TestableReference
                    skipped = "NO">
                    <BuildableReference
        \(testRef)>
                    </BuildableReference>
                 </TestableReference>
              </Testables>
        """
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
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
    \(appRef)>
                </BuildableReference>
             </BuildActionEntry>
    \(testBuildEntry)      </BuildActionEntries>
       </BuildAction>
       <TestAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          shouldUseLaunchSchemeArgsEnv = "YES">
    \(testables)
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
    \(appRef)>
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
    \(appRef)>
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

    """
}

func generate() throws {
    collect = "app"
    let appGroup = buildGroup(sourceDir, appName)

    let hasTests = isDir(testDir) && dirEntries(testDir).contains { $0.hasSuffix(".swift") }
    var testGroup: String?
    if hasTests {
        collect = "test"
        testGroup = buildGroup(testDir, testName)
    }

    let appProduct = uid(), productsGroup = uid(), mainGroup = uid()
    let appTarget = uid(), projectId = uid()
    let appSrcPhase = uid(), appFwPhase = uid(), appResPhase = uid()
    let projCfgList = uid(), appCfgList = uid()
    let projDebug = uid(), projRelease = uid(), appDebug = uid(), appRelease = uid()

    var testProduct = "", testTarget = "", testSrcPhase = "", testFwPhase = "", testResPhase = ""
    var testCfgList = "", testDebug = "", testRelease = "", depId = "", proxyId = ""
    if hasTests {
        testProduct = uid(); testTarget = uid()
        testSrcPhase = uid(); testFwPhase = uid(); testResPhase = uid()
        testCfgList = uid(); testDebug = uid(); testRelease = uid()
        depId = uid(); proxyId = uid()
    }

    productNames[appProduct] = "\(appName).app"
    if hasTests { productNames[testProduct] = "\(testName).xctest" }

    let appSrcBuild = appSources.map { (uid(), $0.0, $0.1) }
    let appResBuild = appResources.map { (uid(), $0.0, $0.1) }
    let testSrcBuild = hasTests ? testSources.map { (uid(), $0.0, $0.1) } : []

    var L: [String] = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
                       "\tobjectVersion = 56;", "\tobjects = {"]

    // PBXBuildFile
    var bf: [String] = []
    for (b, fr, name) in appSrcBuild { bf.append("\t\t\(b) /* \(name) in Sources */ = {isa = PBXBuildFile; fileRef = \(fr) /* \(name) */; };") }
    for (b, fr, name) in appResBuild { bf.append("\t\t\(b) /* \(name) in Resources */ = {isa = PBXBuildFile; fileRef = \(fr) /* \(name) */; };") }
    for (b, fr, name) in testSrcBuild { bf.append("\t\t\(b) /* \(name) in Sources */ = {isa = PBXBuildFile; fileRef = \(fr) /* \(name) */; };") }
    L.append(section("PBXBuildFile", bf))

    // PBXContainerItemProxy
    if hasTests {
        L.append(section("PBXContainerItemProxy", [
            "\t\t\(proxyId) /* PBXContainerItemProxy */ = {", "\t\t\tisa = PBXContainerItemProxy;",
            "\t\t\tcontainerPortal = \(projectId) /* Project object */;", "\t\t\tproxyType = 1;",
            "\t\t\tremoteGlobalIDString = \(appTarget);", "\t\t\tremoteInfo = \(appName);", "\t\t};"]))
    }

    // PBXFileReference
    var frLines: [String] = []
    for f in fileRefs {
        frLines.append("\t\t\(f.id) /* \(f.name) */ = {isa = PBXFileReference; lastKnownFileType = \(f.ftype); path = \"\(f.name)\"; sourceTree = \"<group>\"; };")
    }
    frLines.append("\t\t\(appProduct) /* \(appName).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(appName).app; sourceTree = BUILT_PRODUCTS_DIR; };")
    if hasTests {
        frLines.append("\t\t\(testProduct) /* \(testName).xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = \(testName).xctest; sourceTree = BUILT_PRODUCTS_DIR; };")
    }
    L.append(section("PBXFileReference", frLines))

    // PBXFrameworksBuildPhase
    var fw = emptyPhase(appFwPhase, "Frameworks", "PBXFrameworksBuildPhase")
    if hasTests { fw += "\n" + emptyPhase(testFwPhase, "Frameworks", "PBXFrameworksBuildPhase") }
    L.append(section("PBXFrameworksBuildPhase", [fw]))

    // PBXGroup
    groups.append(Group(id: productsGroup, name: "Products", path: nil, sourceTree: "\"<group>\"",
                        children: [appProduct] + (hasTests ? [testProduct] : []), comment: "Products"))
    groups.append(Group(id: mainGroup, name: nil, path: nil, sourceTree: "\"<group>\"",
                        children: [appGroup] + (testGroup.map { [$0] } ?? []) + [productsGroup], comment: nil))
    var gLines: [String] = []
    for g in groups {
        gLines.append("\t\t\(g.id)" + (g.comment.map { " /* \($0) */" } ?? "") + " = {")
        gLines.append("\t\t\tisa = PBXGroup;")
        gLines.append("\t\t\tchildren = (")
        for c in g.children {
            let nm = nameFor(c)
            gLines.append("\t\t\t\t\(c)" + (nm.map { " /* \($0) */" } ?? "") + ",")
        }
        gLines.append("\t\t\t);")
        if let n = g.name { gLines.append("\t\t\tname = \(n);") }
        if let p = g.path { gLines.append("\t\t\tpath = \(p);") }
        gLines.append("\t\t\tsourceTree = \(g.sourceTree);")
        gLines.append("\t\t};")
    }
    L.append(section("PBXGroup", gLines))

    // PBXNativeTarget
    var nt = nativeTarget(appTarget, appName, appCfgList, [appSrcPhase, appFwPhase, appResPhase],
                          appProduct, "\(appName).app", "com.apple.product-type.application", deps: [])
    if hasTests {
        nt += "\n" + nativeTarget(testTarget, testName, testCfgList, [testSrcPhase, testFwPhase, testResPhase],
                                  testProduct, "\(testName).xctest", "com.apple.product-type.bundle.unit-test",
                                  deps: [(depId, "PBXTargetDependency")])
    }
    L.append(section("PBXNativeTarget", [nt]))

    // PBXProject
    var attrs = ["\t\t\t\t\t\(appTarget) = {", "\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;", "\t\t\t\t\t};"]
    if hasTests {
        attrs += ["\t\t\t\t\t\(testTarget) = {", "\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;",
                  "\t\t\t\t\t\tTestTargetID = \(appTarget);", "\t\t\t\t\t};"]
    }
    var targetsList = ["\t\t\t\t\(appTarget) /* \(appName) */,"]
    if hasTests { targetsList.append("\t\t\t\t\(testTarget) /* \(testName) */,") }
    var pj = ["\t\t\(projectId) /* Project object */ = {", "\t\t\tisa = PBXProject;", "\t\t\tattributes = {",
              "\t\t\t\tBuildIndependentTargetsInParallel = 1;", "\t\t\t\tLastSwiftUpdateCheck = 1520;",
              "\t\t\t\tLastUpgradeCheck = 1520;", "\t\t\t\tTargetAttributes = {"]
    pj += attrs
    pj += ["\t\t\t\t};", "\t\t\t};",
           "\t\t\tbuildConfigurationList = \(projCfgList) /* Build configuration list for PBXProject \"\(appName)\" */;",
           "\t\t\tcompatibilityVersion = \"Xcode 14.0\";", "\t\t\tdevelopmentRegion = en;",
           "\t\t\thasScannedForEncodings = 0;", "\t\t\tknownRegions = (", "\t\t\t\ten,", "\t\t\t\tBase,", "\t\t\t);",
           "\t\t\tmainGroup = \(mainGroup);", "\t\t\tproductRefGroup = \(productsGroup) /* Products */;",
           "\t\t\tprojectDirPath = \"\";", "\t\t\tprojectRoot = \"\";", "\t\t\ttargets = ("]
    pj += targetsList
    pj += ["\t\t\t);", "\t\t};"]
    L.append(section("PBXProject", pj))

    // PBXResourcesBuildPhase
    var rb = filesPhase(appResPhase, "Resources", "PBXResourcesBuildPhase", appResBuild.map { ($0.0, $0.2) })
    if hasTests { rb += "\n" + emptyPhase(testResPhase, "Resources", "PBXResourcesBuildPhase") }
    L.append(section("PBXResourcesBuildPhase", [rb]))

    // PBXSourcesBuildPhase
    var sb = filesPhase(appSrcPhase, "Sources", "PBXSourcesBuildPhase", appSrcBuild.map { ($0.0, $0.2) })
    if hasTests { sb += "\n" + filesPhase(testSrcPhase, "Sources", "PBXSourcesBuildPhase", testSrcBuild.map { ($0.0, $0.2) }) }
    L.append(section("PBXSourcesBuildPhase", [sb]))

    // PBXTargetDependency
    if hasTests {
        L.append(section("PBXTargetDependency", [
            "\t\t\(depId) /* PBXTargetDependency */ = {", "\t\t\tisa = PBXTargetDependency;",
            "\t\t\ttarget = \(appTarget) /* \(appName) */;",
            "\t\t\ttargetProxy = \(proxyId) /* PBXContainerItemProxy */;", "\t\t};"]))
    }

    // XCBuildConfiguration
    var cfgs = [buildConfig(projDebug, "Debug", projectSettings("Debug")),
                buildConfig(projRelease, "Release", projectSettings("Release")),
                buildConfig(appDebug, "Debug", appSettings()),
                buildConfig(appRelease, "Release", appSettings())]
    if hasTests {
        cfgs += [buildConfig(testDebug, "Debug", testSettings()),
                 buildConfig(testRelease, "Release", testSettings())]
    }
    L.append(section("XCBuildConfiguration", cfgs))

    // XCConfigurationList
    var lists = [configList(projCfgList, "PBXProject \"\(appName)\"", projDebug, projRelease),
                 configList(appCfgList, "PBXNativeTarget \"\(appName)\"", appDebug, appRelease)]
    if hasTests { lists.append(configList(testCfgList, "PBXNativeTarget \"\(testName)\"", testDebug, testRelease)) }
    L.append(section("XCConfigurationList", lists))

    L += ["\t};", "\trootObject = \(projectId) /* Project object */;", "}"]

    let projPath = proj.appendingPathComponent("\(appName).xcodeproj")
    try fm.createDirectory(at: projPath.appendingPathComponent("project.xcworkspace"), withIntermediateDirectories: true)
    try (L.joined(separator: "\n") + "\n").write(to: projPath.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
    try ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Workspace\n   version = \"1.0\">\n   <FileRef\n      location = \"self:\">\n   </FileRef>\n</Workspace>\n")
        .write(to: projPath.appendingPathComponent("project.xcworkspace/contents.xcworkspacedata"), atomically: true, encoding: .utf8)

    let schemeDir = projPath.appendingPathComponent("xcshareddata/xcschemes")
    try fm.createDirectory(at: schemeDir, withIntermediateDirectories: true)
    try schemeXML(appTarget, hasTests ? testTarget : nil)
        .write(to: schemeDir.appendingPathComponent("\(appName).xcscheme"), atomically: true, encoding: .utf8)

    print("Wrote \(projPath.path)")
    print("  app: \(appSrcBuild.count) sources, \(appResBuild.count) resources")
    if hasTests { print("  tests: \(testSrcBuild.count) sources (target \(testName))") }
    print("  groups: \(groups.count), shared scheme: \(appName).xcscheme")
}

try generate()
