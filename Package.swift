// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundShade",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SoundShade",
            path: "Sources/SoundShade",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.svg"],
            resources: [
                .copy("Resources/m1ddc"),
                .copy("Resources/StatusIcon.png"),
                .copy("Resources/ProxyAudioDevice.driver"),
                .copy("Resources/AppLogo.svg"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/InstallIcon.svg")
            ]
        )
    ]
)
