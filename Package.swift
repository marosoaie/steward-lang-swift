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
        // package builds against. 0.3 has what `Rule.swiftSource` builds on:
        // `Rule.changedFiles`, a file's contents at the head, the changed
        // lines and the lines after deletions, and `Finding.skipped`.
        .package(url: "https://github.com/marosoaie/swift-steward.git", .upToNextMinor(from: "0.3.0")),
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
        // Parse times on a corpus's largest files (docs/performance.md).
        // Not a product, so packages that depend on this one never build it.
        .executableTarget(
            name: "StewardSwiftBenchmark",
            dependencies: [
                "StewardSwift",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Benchmarks/StewardSwiftBenchmark",
            swiftSettings: swiftSettings
        ),
        // The Dangerfile the end-to-end tests run as its own process, as a
        // workflow runs one. A dependency of the tests, so that building
        // them builds it; not a product.
        .executableTarget(
            name: "SwiftRulesFixture",
            dependencies: ["StewardSwift"],
            path: "Tests/SwiftRulesFixture",
            swiftSettings: swiftSettings
        ),
        // The README's Dangerfile and worked rules, which ReadmeTests holds
        // the README to and runs. Not a product.
        .executableTarget(
            name: "ReadmeDangerfile",
            dependencies: ["StewardSwift"],
            path: "Tests/ReadmeDangerfile",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "StewardSwiftTests",
            dependencies: [
                "StewardSwift",
                "ReadmeDangerfile",
                "SwiftRulesFixture",
                .product(name: "StewardTesting", package: "swift-steward"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
