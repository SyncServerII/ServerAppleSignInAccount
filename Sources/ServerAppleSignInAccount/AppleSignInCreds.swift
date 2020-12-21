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

public class AppleSignInConfiguration: Decodable {
    // From creating a Service Id for your app.
    public let redirectURI: String
    
    // The reverse DNS style app identifier for your iOS app.
    public let clientId: String
    
    // MARK: For generating the client secret; See notes in AppleSignInCreds+ClientSecret.swift
    
    public let keyId: String
    
    public let teamId: String
    
    // Once generated from the Apple developer's website, the key is converted
    // to a single line for the JSON using:
    //      awk 'NF {sub(/\r/, ""); printf "%s\\\\n",$0;}' *.p8
    // Script from https://docs.vmware.com/en/Unified-Access-Gateway/3.0/com.vmware.access-point-30-deploy-config.doc/GUID-870AF51F-AB37-4D6C-B9F5-4BFEB18F11E9.html
    public let privateKey: String
}

public protocol AppleSignInConfigurable {
    var appleSignIn: AppleSignInConfiguration? {get}
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
    weak var delegate: AccountDelegate?

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
    
    required public init?(configuration: Any? = nil, delegate: AccountDelegate?) {
        guard let config = configuration as? AppleSignInConfigurable,
            let appleSignIn = config.appleSignIn else {
            return nil
        }
        
        self.delegate = delegate
        
        self.config = appleSignIn
        super.init()
        baseURL = "appleid.apple.com"
    }
    
    /* An account can be created only if the expiry date in the token has not yet expired. This relies on a minimim of clock skew between the originating server that generated the token expiry date and the server running this library.
    */
    public func canCreateAccount(with userProfile: UserProfile) -> Bool {
        guard let expiryDate = userProfile.extendedProperties[CredentialsAppleSignIn.appleSignInTokenExpiryKey] as? Date else {
            return false
        }
        
        return expiryDate <= Date()
    }
    
    public func needToGenerateTokens(dbCreds: Account?) -> Bool {
        // Making use of a side effect of `needToGenerateTokens`, i.e., setting generateTokens, to either generate the refresh token, or periodically see if the refresh token is valid. When this returns true, `generateTokens` will have been set to a value indicating how to generate tokens.
        
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
        
        // Do we have a new server auth code? If so, then this is our first priority. Because we will need to later call `validateRefreshToken` with a refresh token, and we obtain the refresh token from a new server auth code.
        if let requestServerAuthCode = serverAuthCode {
            if let dbCreds = dbCreds as? AppleSignInCreds,
                let databaseServerAuthCode = dbCreds.serverAuthCode {
                if databaseServerAuthCode != requestServerAuthCode {
                    // We had a prior server auth code, and now have different (new) server auth code.
                    generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                    return true
                }
                // Else: We had a prior server auth code, but no new server auth code.
            }
            else {
                // We don't have an existing server auth code; assume this means this is a new user.
                generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                return true
            }
        }
        // Else: Don't need to check the case where only the db creds have a server auth code (and we have no incoming auth code) because if we stored the server auth code in the database, we used it already.
        
        // We don't have a new server auth code. Is it time to validate the refresh token?
        
        var lastValidation: (refreshDate: Date, refreshToken: String)?
        
        if let dbCreds = dbCreds as? AppleSignInCreds,
            let date = dbCreds.lastRefreshTokenValidation,
            let token = dbCreds.refreshToken {
            lastValidation = (refreshDate: date, refreshToken: token)
        }
        else if let date = lastRefreshTokenValidation, let token = self.refreshToken {
            lastValidation = (refreshDate: date, refreshToken: token)
        }
        
        if let lastValidationInfo = lastValidation,
            GenerateTokens.needToValidateRefreshToken(lastRefreshTokenValidation: lastValidationInfo.refreshDate) {
            generateTokens = .validateRefreshToken(refreshToken: lastValidationInfo.refreshToken)
            return true
        }
        
        generateTokens = .noGeneration
        return false
    }
    
    /// Must have been immediately preceded by a call to `needToGenerateTokens`.
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
        guard let newerCreds = account as? AppleSignInCreds else {
            assertionFailure("Wrong other type of creds!")
            return
        }
        
        if let refreshToken = newerCreds.refreshToken {
            self.refreshToken = refreshToken
        }
        
        if let accessToken = newerCreds.accessToken {
            self.accessToken = accessToken
        }
        
        if let serverAuthCode = newerCreds.serverAuthCode {
            self.serverAuthCode = serverAuthCode
        }
        
        if let lastRefreshTokenValidation = newerCreds.lastRefreshTokenValidation {
            self.lastRefreshTokenValidation = lastRefreshTokenValidation
        }
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
        guard let creds = AppleSignInCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        creds.accountCreationUser = user
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
        
        guard let result = AppleSignInCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        result.accountCreationUser = user
        
        result.serverAuthCode = databaseCreds.serverAuthCode
        result.accessToken = databaseCreds.idToken
        result.refreshToken = databaseCreds.refreshToken
        result.lastRefreshTokenValidation = databaseCreds.lastRefreshTokenValidation

        return result
    }
}
