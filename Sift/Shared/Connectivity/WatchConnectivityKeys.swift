import Foundation

/// Keys shared by the watch (sender) and phone (receiver) so both ends agree on
/// the shape of the messages passed over `WatchConnectivity`.
public enum WCKeys {
    /// Metadata attached to a transferred audio file.
    public static let entryID = "entryID"
    public static let createdAt = "createdAt"
    public static let duration = "duration"
    /// A best-effort transcript captured on the watch, when available.
    public static let watchTranscript = "watchTranscript"

    /// Message type discriminator.
    public static let messageType = "messageType"
    public static let typeNewEntry = "newEntry"
}
