
import Foundation
import ServerAccount
import ServerShared
import HeliumLogger
import LoggerAPI

public class NotificationRequest: RequestMessage, NeedingRequestBodyData {
    public var data:Data!
    public var sizeOfDataInBytes:Int!
    
    public init() {}
    
    public func valid() -> Bool {
        true
    }
    
    public static func decode(_ dictionary: [String : Any]) throws -> RequestMessage {
        // Just a stub.
        return NotificationRequest()
    }
}

// expect the body data of the request from Apple, as a String, to be JSON:
//  {"payload" : "-- SNIP-- JWT"}
struct ApplePayload: Decodable {
    let payload: String // JWT
}

extension NotificationRequest {
    func processData() {
        guard let data = data else {
            Log.error("Could not get data from NotificationRequest")
            return
        }
        
        guard let payload = try? JSONDecoder().decode(ApplePayload.self, from: data) else {
            Log.error("Could not get ApplePayload from NotificationRequest data")
            return
        }

        Log.info("payload JWT: \(payload.payload)")
    }
}
