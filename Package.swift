// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ViggoClean",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ViggoClean", targets: ["ViggoClean"])],
    targets: [
        .target(name: "ViggoCleanCore"),
        .target(name: "ViggoCleanPresentation", dependencies: ["ViggoCleanCore"]),
        .executableTarget(name: "ViggoClean", dependencies: ["ViggoCleanCore", "ViggoCleanPresentation"]),
        .testTarget(name: "ViggoCleanCoreTests", dependencies: ["ViggoCleanCore"]),
        .testTarget(name: "ViggoCleanPresentationTests", dependencies: ["ViggoCleanPresentation", "ViggoCleanCore"])
    ]
)
