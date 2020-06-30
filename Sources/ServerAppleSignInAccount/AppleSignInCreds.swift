//
//  AppleSignInCreds.swift
//  Server
//
//  Created by Christopher G Prince on 10/2/19.
//

import Foundation
import CredentialsAppleSignIn
import ServerShared
import Kitura
import HeliumLogger
import LoggerAPI
import Credentials
import ServerAccount

public protocol AppleSignInConfiguration {
    // From creating a Service Id for your app.
    var redirectURI: String {get}
    
    // The reverse DNS style app identifier for your iOS app.
    var clientId: String {get}
    
    // MARK: For generating the client secret; See notes in AppleSignInCreds+ClientSecret.swift
    
    var keyId: String {get}
    
    var teamId: String {get}
    
    // Once generated from the Apple developer's website, the key is converted
    // to a single line for the JSON using:
    //      awk 'NF {sub(/\r/, ""); printf "%s\\\\n",$0;}' *.p8
    // Script from https://docs.vmware.com/en/Unified-Access-Gateway/3.0/com.vmware.access-point-30-deploy-config.doc/GUID-870AF51F-AB37-4D6C-B9F5-4BFEB18F11E9.html
    var privateKey: String {get}
}

// For general strategy used with Apple Sign In-- see
// https://stackoverflow.com/questions/58178187
// https://github.com/crspybits/CredentialsAppleSignIn and
// https://forums.developer.apple.com/message/386237

public class AppleSignInCreds: AccountAPICall, Account {
    enum AppleSignInCredsError: Swift.Error {
        case noCallToNeedToGenerateTokens
        case failedCreatingClientSecret
        case couldNotSignJWT
        case noPrivateKeyData
    }
    
    public static let accountScheme: AccountScheme = .appleSignIn
    public let accountScheme: AccountScheme = AppleSignInCreds.accountScheme
    public let owningAccountsNeedCloudFolderName: Bool = false
    
    public weak var delegate: AccountDelegate?
    
    public var accountCreationUser: AccountCreationUser?
    
    struct DatabaseCreds: Codable {
        // Storing the serverAuthCode in the database so that I don't try to generate a refresh token from the same serverAuthCode twice.
        let serverAuthCode: String?
        
        let idToken: String
        let refreshToken: String?
        
        // Because Apple imposes limits about how often you can validate the refresh token.
        let lastRefreshTokenValidation: Date?
    }
    
    // This is actually an idToken, in Apple's terms.
    public var accessToken: String!
    private var serverAuthCode:String?
    
    // Obtained via the serverAuthCode
    var refreshToken: String?
    
    var lastRefreshTokenValidation: Date?
    
    enum GenerateTokens {
        case noGeneration
        case generateRefreshToken(serverAuthCode: String)
        case validateRefreshToken(refreshToken: String)
        
        // Apple says we can't validate tokens more than once per day.
        static let minimumValidationDuration: TimeInterval = 60 * 60 * 24
        
        static func needToValidateRefreshToken(lastRefreshTokenValidation: Date) -> Bool {
            let timeIntervalSinceLastValidation = Date().timeIntervalSince(lastRefreshTokenValidation)
            return timeIntervalSinceLastValidation >= minimumValidationDuration
        }
    }
    
    private(set) var generateTokens: GenerateTokens?
    let config: AppleSignInConfiguration
    
    required public init?(configuration: Any? = nil) {
        guard let config = configuration as? AppleSignInConfiguration else {
            return nil
        }
        
        self.config = config
        super.init()
        baseURL = "appleid.apple.com"
    }
    
    public func canCreateAccount(with userProfile: UserProfile) -> Bool {
        guard let expiryDate = userProfile.extendedProperties[CredentialsAppleSignIn.appleSignInTokenExpiryKey] as? Date else {
            return false
        }
        
        return expiryDate <= Date()
    }
    
    public func needToGenerateTokens(dbCreds: Account?) -> Bool {
        // Making use of a side effect of `needToGenerateTokens`, i.e., setting generateTokens, to either generate the refresh token, or periodically see if the refresh token is valid.
        
        // Since a) presumably we can't use a serverAuthCode more than once, and b) Apple throttles use of the refresh token, don't generate tokens unless we have a delegate to save the tokens.
        guard let _ = delegate else {
            return false
        }

        if let dbCreds = dbCreds {
            guard dbCreds is AppleSignInCreds else {
                Log.error("dbCreds were not AppleSignInCreds")
                return false
            }
        }
        
        // The tokens in `self` are assumed to be from the request headers -- i.e., they are new.
        
        // Do we have a new server auth code? If so, then this is our first priority. Because subsequent id tokens will be generated from the refresh token created from the server auth code?
        if let requestServerAuthCode = serverAuthCode {
            if let dbCreds = dbCreds as? AppleSignInCreds,
                let databaseServerAuthCode = dbCreds.serverAuthCode {
                if databaseServerAuthCode != requestServerAuthCode {
                    generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                    return true
                }
            }
            else {
                // We don't have an existing server auth code; assume this means this is a new user.
                generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                return true
            }
        }
        // Don't need to check the case where only the db creds have a server auth code because if we stored the server auth code in the database, we used it already.
        
        // Not using a new server auth code. Is it time to generate a new id token?
        var lastRefresh: Date?
        var refreshToken = ""
        
        if let dbCreds = dbCreds as? AppleSignInCreds,
            let last = dbCreds.lastRefreshTokenValidation,
            let token = dbCreds.refreshToken {
            lastRefresh = last
            refreshToken = token
        }
        else if let _ = lastRefreshTokenValidation, let token = self.refreshToken {
            lastRefresh = lastRefreshTokenValidation
            refreshToken = token
        }
        
        if let last = lastRefresh,
            GenerateTokens.needToValidateRefreshToken(lastRefreshTokenValidation: last) {
            generateTokens = .validateRefreshToken(refreshToken: refreshToken)
            return true
        }
        
        generateTokens = .noGeneration
        return false
    }
    
    public func generateTokens(completion:@escaping (Swift.Error?)->()) {
        guard let generateTokens = generateTokens else {
            completion(AppleSignInCredsError.noCallToNeedToGenerateTokens)
            return
        }
        
        switch generateTokens {
        case .noGeneration:
            self.generateTokens = nil
            completion(nil)
            
        case .generateRefreshToken(serverAuthCode: let serverAuthCode):
            generateRefreshToken(serverAuthCode: serverAuthCode) { [weak self] error in
                self?.generateTokens = nil
                completion(error)
            }
            
        case .validateRefreshToken(refreshToken: let refreshToken):
            validateRefreshToken(refreshToken: refreshToken) { [weak self] error in
                self?.generateTokens = nil
                completion(error)
            }
        }
    }
    
    public func merge(withNewer account: Account) {
    }
    
    public static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any] {
        var result = [String: Any]()
        
        if let authCode = headers[ServerConstants.HTTPOAuth2AuthorizationCodeKey] {
            result[ServerConstants.HTTPOAuth2AuthorizationCodeKey] = authCode
        }
        
        if let idToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = idToken
        }
        
        return result
    }
    
    public static func fromProperties(_ properties: AccountProperties, user:AccountCreationUser?, configuration: Any?, delegate:AccountDelegate?) -> Account? {
        guard let creds = AppleSignInCreds(configuration: configuration) else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.serverAuthCode =
            properties.properties[ServerConstants.HTTPOAuth2AuthorizationCodeKey] as? String
        return creds
    }
    
    public func toJSON() -> String? {
        let databaseCreds = DatabaseCreds(serverAuthCode: serverAuthCode, idToken: accessToken, refreshToken: refreshToken, lastRefreshTokenValidation: lastRefreshTokenValidation)
        
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(databaseCreds) else {
            Log.error("Failed encoding DatabaseCreds")
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    public static func fromJSON(_ json: String, user: AccountCreationUser, configuration: Any?, delegate: AccountDelegate?) throws -> Account? {
    
        guard let data = json.data(using: .utf8) else {
            return nil
        }
    
        let decoder = JSONDecoder()
        guard let databaseCreds = try? decoder.decode(DatabaseCreds.self, from: data) else {
            return nil
        }
        
        guard let result = AppleSignInCreds(configuration: configuration) else {
            return nil
        }
        
        result.delegate = delegate
        result.accountCreationUser = user
        
        result.serverAuthCode = databaseCreds.serverAuthCode
        result.accessToken = databaseCreds.idToken
        result.refreshToken = databaseCreds.refreshToken
        result.lastRefreshTokenValidation = databaseCreds.lastRefreshTokenValidation

        return result
    }
}
