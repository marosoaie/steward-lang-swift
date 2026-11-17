// swift-tools-version: 6.2
import PackageDescription

// swift-steward's settings, on every target (AGENTS.md).
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]

let package = Package(
    name: "steward-lang-swift",
    // Steward needs the 26 releases, whose standard library has `Span`;
    // Linux has no floor.
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StewardSwift", targets: ["StewardSwift"]),
    ],
    dependencies: [
        // One minor release of Steward: a 0.x minor may break the API this
        // package builds against. 0.2 for now, which has all that the model
        // needs; the requirement moves to 0.3 before `Rule.swiftSource`,
        // which reads files through 0.3's public API.
        .package(url: "https://github.com/marosoaie/swift-steward.git", .upToNextMinor(from: "0.2.0")),
        // A range of majors (AGENTS.md). SwiftPM picks the newest in it, and
        // a parser older than the code it reads skips that file, so the upper
        // bound moves soon after each swift-syntax major. CI also builds
        // against the lower bound.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"605.0.0"),
    ],
    targets: [
        // A Dangerfile's rules about the structure of Swift source. It
        // re-exports SwiftSyntax, so a Dangerfile that reaches for raw syntax
        // nodes imports only StewardSwift.
        .target(
            name: "StewardSwift",
            dependencies: [
                .product(name: "Steward", package: "swift-steward"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "StewardSwiftTests",
            dependencies: [
                "StewardSwift",
                .product(name: "StewardTesting", package: "swift-steward"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
