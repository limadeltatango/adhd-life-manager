// swift-tools-version: 5.9
// Swift Playgrounds iPad app. AppleProductTypes is supplied by Apple's toolchain.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Life Manager",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Life Manager",
            targets: ["AppModule"],
            bundleIdentifier: "com.limadeltatango.lifemanager",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .checkmark),
            accentColor: .presetColor(.teal),
            supportedDeviceFamilies: [
                .phone,
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
