// swift-tools-version: 6.1
// The web build of the port. The game's Swift files are the same ones the Xcode project
// compiles against Apple's SwiftUI (and tests there, SwiftUI2048Tests); here they link
// SwiftUIWeb's SwiftUI (vendor/swiftui-web, a pinned submodule) and, on wasm, its Foundation
// and Combine shadows in place of Apple's frameworks. Build it with `scripts/build-web.sh`.
import PackageDescription

let shadows: [Target.Dependency] = [
    .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
    .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
]

let package = Package(
    name: "SwiftUI2048",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "SwiftUI2048", targets: ["SwiftUI2048"]),
    ],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "vendor/swiftui-web"),
        .package(name: "Shadows", path: "vendor/swiftui-web/Packages/Shadows"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftUI2048",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb", condition: .when(platforms: [.wasi])),
                .product(name: "SwiftUIWebNative", package: "SwiftUIWeb", condition: .when(platforms: [.macOS])),
                // The harness build reads the page's URL (SwiftUI2048App.makeGameLogic, `-DHARNESS`).
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ] + shadows,
            path: "SwiftUI2048",
            exclude: ["Preview Content"],
            resources: [.process("Assets.xcassets")],
            // Swift 5 mode, as upstream's Xcode target (SWIFT_VERSION 5.0). The harness build
            // (`scripts/build-web.sh --harness`, SWIFTUI2048_HARNESS=1 in the environment)
            // defines HARNESS: SwiftUI2048App.makeGameLogic then reads the page's URL. The
            // PackageToJS plugin runs its own build, so a `-Xswiftc -D` on the command line
            // would not reach the compiler; the manifest decides.
            swiftSettings: [.swiftLanguageMode(.v5)] + (Context.environment["SWIFTUI2048_HARNESS"] == "1" ? [.define("HARNESS")] : []),
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
    ]
)
