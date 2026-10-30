// swift-tools-version: 5.10
import PackageDescription

// llama.cpp comes from the official prebuilt XCFramework on Apple platforms
// (fetched by scripts/bootstrap.sh into Vendor/). On Linux, where we only run
// tests, it links against a system/pip-provided libllama (see scripts/test-linux.sh).
#if os(Linux)
let llama: Target = .systemLibrary(name: "llama", path: "Sources/CLlamaLinux")
#else
let llama: Target = .binaryTarget(name: "llama", path: "Vendor/llama.xcframework")
#endif

var products: [Product] = [
    .library(name: "WritingCore", targets: ["WritingCore"]),
    .library(name: "LlamaRuntime", targets: ["LlamaRuntime"]),
]

var targets: [Target] = [
    .target(
        name: "WritingCore",
        resources: [.copy("Resources/prompts.json"), .copy("Resources/models.json")]
    ),
    llama,
    .target(name: "LlamaRuntime", dependencies: ["WritingCore", "llama"]),
    .testTarget(name: "WritingCoreTests", dependencies: ["WritingCore"], resources: [.copy("Fixtures")]),
    .testTarget(name: "LlamaRuntimeTests", dependencies: ["LlamaRuntime", "WritingCore"]),
]

#if !os(Linux)
products.append(.library(name: "KeyboardUI", targets: ["KeyboardUI"]))
targets.append(.target(name: "KeyboardUI", dependencies: ["WritingCore"]))
#endif

let package = Package(
    name: "WriterKit",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: products,
    targets: targets
)
