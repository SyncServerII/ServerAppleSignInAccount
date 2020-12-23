
import Foundation
import ServerAccount
import ServerShared

public class NotificationRequest: RequestMessage, NeedingRequestBodyData {
    public var data:Data!
    public var sizeOfDataInBytes:Int!
    
    required public init() {}
    
    public func valid() -> Bool {
        true
    }
    
    public static func decode(_ dictionary: [String : Any]) throws -> RequestMessage {
        // Just a stub.
        return NotificationRequest()
    }
}


