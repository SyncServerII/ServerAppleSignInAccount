// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ServerAppleSignInAccount",
    products: [
        .library(
            name: "ServerAppleSignInAccount",
            targets: ["ServerAppleSignInAccount"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/SyncServerII/ServerAccount.git", from: "0.0.3"),
        .package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        //.package(name: "SwiftJWT", url: "https://github.com/Kitura/Swift-JWT.git", from: "3.6.200"),
        .package(name: "SwiftJWT", url: "https://github.com/IBM-Swift/Swift-JWT.git", from: "3.5.3"),

        .package(url: "https://github.com/crspybits/CredentialsAppleSignIn.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "ServerAppleSignInAccount",
            dependencies: ["ServerAccount", "SwiftJWT", "CredentialsAppleSignIn", "ServerShared"
            ]),
        .testTarget(
            name: "ServerAppleSignInAccountTests",
            dependencies: ["ServerAppleSignInAccount"]),
    ]
)
