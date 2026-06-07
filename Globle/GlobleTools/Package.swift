// swift-tools-version: 5.9
import PackageDescription

// Pure-Swift replacements for the offline generator scripts. These are developer
// tools (run on macOS), not part of the shipped app:
//
//   swift run build-countries   # regenerate Globle/Resources/countries.json
//   swift run make-icon         # regenerate the app icon
//   swift run make-xcodeproj    # regenerate Globle.xcodeproj
//
let package = Package(
    name: "GlobleTools",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "build-countries"),
        .executableTarget(name: "make-icon"),
        .executableTarget(name: "make-xcodeproj"),
    ]
)
