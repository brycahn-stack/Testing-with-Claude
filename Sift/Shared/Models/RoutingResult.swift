import Foundation

/// The outcome of handing a `JournalEntry` off to one destination (Reminders,
/// Calendar, a log, etc.). An entry can have several — one per destination that
/// acted on it.
public struct RoutingResult: Codable, Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case success          // Landed in the destination.
        case failed           // Destination errored (e.g. permission denied).
        case needsConfirmation // Created but awaiting the user's OK.
    }

    public let id: UUID
    /// Stable identifier of the destination that produced this result.
    public let destinationID: String
    /// Human-readable name of the destination, e.g. "Reminders".
    public let destinationName: String
    public let status: Status
    /// What was created, e.g. "Reminder: Call the dentist".
    public let detail: String
    /// Identifier of the created object in the external system (EKReminder id, …),
    /// so it can later be updated or deleted.
    public let externalID: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        destinationID: String,
        destinationName: String,
        status: Status,
        detail: String,
        externalID: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.status = status
        self.detail = detail
        self.externalID = externalID
        self.timestamp = timestamp
    }
}
