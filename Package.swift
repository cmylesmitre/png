// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "PNG",
    products:
    [
        .library(   name: "png",                        targets: ["PNG"]),
        
    ],
    targets: 
    [
        .target(name: "PNG",                        dependencies: [],       path: "sources/png"),
    ],
    swiftLanguageVersions: [.v5]
)
