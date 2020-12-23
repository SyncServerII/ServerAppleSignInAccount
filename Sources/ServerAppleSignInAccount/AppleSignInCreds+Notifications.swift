//
//  AppleSignInCreds+Notifications.swift
//  
//
//  Created by Christopher G Prince on 6/29/20.
//

// For Apple's "server-to-server notifications"
// Just a stub so far. Apple hasn't published specs on this yet for Apple Sign In.

import Foundation
import ServerAccount
import ServerShared

public class AppleServerServerNotification: ControllerProtocol {
    public static let endpoint = ServerEndpoint("AppleServerServerNotification", method: .post, requestMessageType: NotificationRequest.self, authenticationLevel: .none)
    
    public init() {}
    
    public static func setup() -> Bool {
        return true
    }
    
    public func update(request: NotificationRequest) {
        request.processData()
    }
}
