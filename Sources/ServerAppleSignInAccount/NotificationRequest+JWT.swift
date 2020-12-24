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

extension NotificationRequest {
    enum NotificationRequestError: Swift.Error {
        case failureResult(FailureResult)
        case couldNotVerifyToken(
            ApplePublicKey<AppleSignInClaims>.TokenVerificationResult)
        case generic(String)
    }
    
    // Empahasis: This endpoint is unauthenticated. i.e., no oauth token comes in the headers.
    public static let endpoint = ServerEndpoint("AppleServerServerNotification", method: .post, requestMessageType: NotificationRequest.self, authenticationLevel: .none)

    // Expect the body data of the REST server-to-server notification request from Apple, as a String, to be JSON:
    //      {"payload" : "-- SNIP -- JWT"}
    // I determined this experimentally.
    struct ApplePayload: Decodable {
        let payload: String // JWT
    }

    public func getEventFromJWT(clientId: String, completion: @escaping (Swift.Result<AppleSignInClaims, Swift.Error>)->()) {
        guard let data = data else {
            let message = "Could not get data from NotificationRequest"
            Log.error(message)
            completion(.failure(NotificationRequestError.generic(message)))
            return
        }
        
        guard let jwt = try? JSONDecoder().decode(ApplePayload.self, from: data) else {
            let message = "Could not get ApplePayload from NotificationRequest data"
            Log.error(message)
            completion(.failure(NotificationRequestError.generic(message)))
            return
        }
        
        ApplePublicKey.httpFetch { (result: Swift.Result<ApplePublicKey<AppleSignInClaims>, FailureResult>) in
            let applePublicKey:ApplePublicKey<AppleSignInClaims>
            switch result {
            case .success(let key):
                applePublicKey = key
                
            case .failure(let failure):
                completion(.failure(NotificationRequestError.failureResult(failure)))
                return
            }
            
            let verifyResult = applePublicKey.verifyToken(jwt.payload, clientId: clientId)
            switch verifyResult {
            case .success(let claims):
                completion(.success(claims))
            default:
                completion(.failure(NotificationRequestError.couldNotVerifyToken(verifyResult)))
            }
        }
    }
}
