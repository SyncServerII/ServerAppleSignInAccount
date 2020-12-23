//
//  AppleSignInCreds+Notifications.swift
//  
//
//  Created by Christopher G Prince on 6/29/20.
//

// For Apple's "server-to-server notifications"

import Foundation
import ServerAccount
import ServerShared
import AppleJWTDecoder
import HeliumLogger
import LoggerAPI

public class AppleServerServerNotification: ControllerProtocol {
    enum AppleServerServerNotificationError: Swift.Error {
        case failureResult(FailureResult)
        case couldNotVerifyToken(ApplePublicKey<AppleSignInClaims>.TokenVerificationResult)
        case generic(String)
    }
    
    public static let endpoint = ServerEndpoint("AppleServerServerNotification", method: .post, requestMessageType: NotificationRequest.self, authenticationLevel: .none)
    
    public init() {}
    
    public static func setup() -> Bool {
        return true
    }

    // Expect the body data of the REST server-to-server notification request from Apple, as a String, to be JSON:
    //  {"payload" : "-- SNIP -- JWT"}
    struct ApplePayload: Decodable {
        let payload: String // JWT
    }

    func getEventFromJWT(request: NotificationRequest, clientId: String, completion: @escaping (Swift.Result<AppleSignInClaims, Swift.Error>)->()) throws {
        guard let data = request.data else {
            let message = "Could not get data from NotificationRequest"
            Log.error(message)
            completion(.failure(AppleServerServerNotificationError.generic(message)))
            return
        }
        
        guard let jwt = try? JSONDecoder().decode(ApplePayload.self, from: data) else {
            let message = "Could not get ApplePayload from NotificationRequest data"
            Log.error(message)
            completion(.failure(AppleServerServerNotificationError.generic(message)))
            return
        }

        Log.info("payload JWT: \(jwt.payload)")
        
        ApplePublicKey.httpFetch { (result: Swift.Result<ApplePublicKey<AppleSignInClaims>, FailureResult>) in
            let applePublicKey:ApplePublicKey<AppleSignInClaims>
            switch result {
            case .success(let key):
                applePublicKey = key
                
            case .failure(let failure):
                completion(.failure(AppleServerServerNotificationError.failureResult(failure)))
                return
            }
            
            let verifyResult = applePublicKey.verifyToken(jwt.payload, clientId: clientId)
            switch verifyResult {
            case .success(let claims):
                Log.info("claims: \(claims)")
                completion(.success(claims))
            default:
                completion(.failure(AppleServerServerNotificationError.couldNotVerifyToken(verifyResult)))
            }
        }
    }
}
