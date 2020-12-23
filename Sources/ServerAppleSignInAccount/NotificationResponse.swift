
import Foundation
import ServerShared

// Apple doesn't need this; just satisfying SyncServerII.
public class NotificationResponse : ResponseMessage {
    required public init() {}

    public var responseType: ResponseType {
        return .json
    }

    public static func decode(_ dictionary: [String: Any]) throws -> NotificationResponse {
        return NotificationResponse()
    }
}
