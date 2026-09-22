// swift-tools-version: 6.0
import PackageDescription
var products: [Product] = [.library(name: "ToolIsleCore", targets: ["ToolIsleCore"])]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "ToolIsleCore", path: "ToolIsle/Core"),
    .testTarget(name: "ToolIsleCoreTests", dependencies: ["ToolIsleCore"], path: "ToolIsle/Tests")
]
#if os(macOS)
products.append(.executable(name: "ToolIsle", targets: ["ToolIsleApp"]))
dependencies.append(.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"))
targets.append(.executableTarget(name: "ToolIsleApp", dependencies: ["ToolIsleCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")], path: "ToolIsle/App", resources: [.copy("Resources")]))
#endif
let package = Package(name: "ToolIsle", platforms: [.macOS(.v14)], products: products, dependencies: dependencies, targets: targets, swiftLanguageModes: [.v5])
