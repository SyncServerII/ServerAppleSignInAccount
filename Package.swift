// swift-tools-version:5.3
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
        .package(url: "https://github.com/SyncServerII/ServerAccount.git", from: "0.0.1"),
        .package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        .package(name: "SwiftJWT", url: "https://github.com/IBM-Swift/Swift-JWT.git", from: "3.6.1"),
        .package(url: "https://github.com/crspybits/CredentialsAppleSignIn.git", from: "0.0.1"),
        .package(url: "https://github.com/SyncServerII/AppleJWTDecoder.git", from: "0.0.1"),
        .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.9.1"),
    ],
    targets: [
        .target(
            name: "ServerAppleSignInAccount",
            dependencies: ["ServerAccount", "SwiftJWT", "CredentialsAppleSignIn",
                 "Kitura", "ServerShared", "AppleJWTDecoder"
            ]),
        .testTarget(
            name: "ServerAppleSignInAccountTests",
            dependencies: ["ServerAppleSignInAccount", "Kitura"]),
    ]
)
