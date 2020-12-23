
import Foundation
import ServerShared

// Apple doesn't need this; just satisfying SyncServerII.
public class NotificationResponse: ResponseMessage {
    public init() {}
    public var responseType:ResponseType = .json
}
