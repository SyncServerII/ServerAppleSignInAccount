//
//  AccountAuthenticationTests_AppleSignIn.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/5/19.
//

/*
    Testing procedure:
    1) Run the modified juice app and get an authorizationCode
        - Put this into the json file

    2) Use tests below to generate a refresh token
        - Put this into the json file
 */

import XCTest
import LoggerAPI
import HeliumLogger
@testable import ServerAppleSignInAccount
import ServerAccount

struct ServerAppleSignInJSON: Decodable, AppleSignInConfigurable {
    let appleSignIn: AppleSignInConfiguration?
    let authorizationCode: String?
    let refreshToken: String?
    
    static func load(from url: URL) -> Self {
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not get data from url")
        }

        let decoder = JSONDecoder()

        guard let object = try? decoder.decode(Self.self, from: data) else {
            fatalError("Could not decode the json")
        }

        return object
    }
}

class AccountAuthenticationTests_AppleSignIn: XCTestCase {
    let config = ServerAppleSignInJSON.load(from: URL(fileURLWithPath: "/Users/chris/Desktop/Apps/SyncServerII/Private/ServerAppleSignInAccount/token.json"))

    func testClientSecretGenerationWorks() {
        guard let appleSignInCreds = AppleSignInCreds(configuration: config, delegate: nil) else {
            XCTFail()
            return
        }
        
        do {
            _ = try appleSignInCreds.createClientSecret()
        } catch let error {
            XCTFail("\(error)")
        }
    }

    // This has to be tested by hand-- since the authorization codes expire in 5 minutes and can only be used once. Before running this test, populate an auth code into the apple1 account first-- this can be generated from the iOS app.
    func testGenerateRefreshToken() {
        guard let appleSignInCreds = AppleSignInCreds(configuration: config, delegate: nil) else {
            XCTFail()
            return
        }
                
        guard let authorizationCode = config.authorizationCode else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "generate")
        appleSignInCreds.generateRefreshToken(serverAuthCode: authorizationCode) { error in
            // XCTAssertTrue failed - Optional(ServerAccount.GenerateTokensError.badStatusCode(Optional(KituraNet.HTTPStatusCode.badRequest)))
            // is a typical error here. E.g., when I do two successive tets back to back
            XCTAssert(error == nil, "\(String(describing: error))")
            
            XCTAssert(appleSignInCreds.accessToken != nil)
            XCTAssert(appleSignInCreds.refreshToken != nil)
            print("appleSignInCreds.accessToken: \(String(describing: appleSignInCreds.accessToken))")
            print("appleSignInCreds.refreshToken: \(String(describing: appleSignInCreds.refreshToken))")
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    // This also has to be tested by hand-- since a refresh token can only be used at most every 24 hours
    func testValidateRefreshToken() {
        guard let appleSignInCreds = AppleSignInCreds(configuration: config, delegate: nil) else {
            XCTFail()
            return
        }
        
        guard let refreshToken = config.refreshToken else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "refresh")
        
        appleSignInCreds.validateRefreshToken(refreshToken: refreshToken) { error in
            XCTAssert(error == nil, "\(String(describing: error))")

            XCTAssert(appleSignInCreds.lastRefreshTokenValidation != nil)
            
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    class CredsDelegate: AccountDelegate {
        func saveToDatabase(account: Account) -> Bool {
            return false
        }
    }
    
    // No dbCreds, serverAuthCode, lastRefreshTokenValidation, refreshToken
    func testNeedToGenerateTokensNoGeneration() {
        guard let appleSignInCreds = AppleSignInCreds(configuration: config, delegate: nil) else {
            XCTFail()
            return
        }
        
        let delegate = CredsDelegate()
        appleSignInCreds.delegate = delegate
                        
        let result = appleSignInCreds.needToGenerateTokens(dbCreds: nil)
        XCTAssert(!result)
        
        switch appleSignInCreds.generateTokens {
        case .some(.noGeneration):
            break
        default:
            XCTFail()
        }
    }
}
