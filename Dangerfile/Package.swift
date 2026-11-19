// swift-tools-version: 6.2
// The checks Steward runs on this repository's own pull requests, in
// ci.yml's macos-tests job through steward-action. Unlike a user's
// Dangerfile, it depends on the checkout it sits in, so every pull request
// is checked by its own model and rules. The root manifest never depends on
// it. Its Package.resolved is committed: steward-action's cache key is its
// hash (the root's stays uncommitted).
import PackageDescription

// The root's settings (AGENTS.md).
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]

let package = Package(
    name: "Dangerfile",
    platforms: [.macOS(.v26)],
    dependencies: [
        // `name:` keeps the identity the products are looked up by, whatever
        // the checkout's directory is called.
        .package(name: "steward-lang-swift", path: ".."),
        // The Steward the root requires, for StewardTesting.
        .package(url: "https://github.com/marosoaie/swift-steward.git", .upToNextMinor(from: "0.3.0")),
    ],
    targets: [
        .executableTarget(
            name: "Dangerfile",
            dependencies: [
                .product(name: "Steward", package: "swift-steward"),
                .product(name: "StewardSwift", package: "steward-lang-swift"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DangerfileTests",
            dependencies: ["Dangerfile", .product(name: "StewardTesting", package: "swift-steward")],
            swiftSettings: swiftSettings
        ),
    ]
)
