// swift-tools-version: 6.0
import PackageDescription

// Lightweight shared-model checks, independent of the iPhone UI and downloaded-model libraries.
let package = Package(
    name: "GardeCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "GardeCore", targets: ["GardeCore"])],
    targets: [
        .target(name: "GardeCore", path: "Shared", exclude: ["Theme.swift"]),
        .testTarget(name: "InventoryContractTests", dependencies: ["GardeCore"], path: "GardeTests",
            exclude: ["AIReleaseTests.swift", "GardeTests.swift", "KitchenUpgradeTests.swift", "PantryReleaseTests.swift"],
            sources: ["InventoryContractTests.swift"]),
    ],
    swiftLanguageModes: [.v5]
)
