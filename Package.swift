// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SafeCleaner",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SafeCleaner", targets: ["SafeCleaner"])],
    targets: [
        .target(name: "SafeCleanerCore"),
        .target(name: "SafeCleanerPresentation", dependencies: ["SafeCleanerCore"]),
        .executableTarget(name: "SafeCleaner", dependencies: ["SafeCleanerCore", "SafeCleanerPresentation"]),
        .testTarget(name: "SafeCleanerCoreTests", dependencies: ["SafeCleanerCore"]),
        .testTarget(name: "SafeCleanerPresentationTests", dependencies: ["SafeCleanerPresentation", "SafeCleanerCore"])
    ]
)
