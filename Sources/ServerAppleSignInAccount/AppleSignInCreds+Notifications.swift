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

public struct NotificationRequest: RequestMessage {
    public init() {}
    
    public func valid() -> Bool {
        false
    }
    
    public static func decode(_ dictionary: [String : Any]) throws -> RequestMessage {
        // Just a stub.
        throw AppleSignInCreds.AppleSignInCredsError.couldNotSignJWT
    }
}

public class AppleServerServerNotification: ControllerProtocol {
    public static let endpoint = ServerEndpoint("AppleServerServerNotification", method: .post, requestMessageType: NotificationRequest.self, authenticationLevel: .none)
    
    public init() {}
    
    public static func setup() -> Bool {
        return true
    }
}
