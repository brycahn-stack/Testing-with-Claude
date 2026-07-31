import Foundation
import Combine

/// How much latitude the user gives each destination.
///
/// The dial between magic and control: asking permission for every reminder is
/// friction, but silently emailing someone is a disaster. Defaults are set per
/// destination in `TrustSettings.defaultLevel` — anything other people see
/// ("always ask") versus private bookkeeping ("auto when confident").
public enum TrustLevel: String, Codable, CaseIterable, Sendable {
    case alwaysAsk
    case autoWhenConfident

    public var displayName: String {
        switch self {
        case .alwaysAsk:         return "Always ask"
        case .autoWhenConfident: return "Auto when confident"
        }
    }

    public var blurb: String {
        switch self {
        case .alwaysAsk:         return "Every action waits for your approval."
        case .autoWhenConfident: return "Runs on its own above 80% confidence."
        }
    }
}

@MainActor
public final class TrustSettings: ObservableObject {
    public static let autoApproveThreshold = 0.8

    @Published public private(set) var levels: [String: TrustLevel] = [:]

    private let defaultsKey = "sift.trustLevels"

    public init() {
        if let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            levels = raw.compactMapValues(TrustLevel.init(rawValue:))
        }
    }

    /// Conservative by default for anything that leaves the device — and for
    /// person notes, where even a *created* file puts words in a page the user
    /// curates about someone they know.
    public static func defaultLevel(for destinationID: String) -> TrustLevel {
        switch destinationID {
        case "google.gmail", "google.calendar", "calendar", "obsidian.person":
            return .alwaysAsk
        default:
            return .autoWhenConfident
        }
    }

    public func level(for destinationID: String) -> TrustLevel {
        levels[destinationID] ?? Self.defaultLevel(for: destinationID)
    }

    public func setLevel(_ level: TrustLevel, for destinationID: String) {
        levels[destinationID] = level
        UserDefaults.standard.set(levels.mapValues(\.rawValue), forKey: defaultsKey)
    }

    /// Whether a proposal may skip the review queue. High-stakes actions (sending
    /// mail, inviting people) never auto-approve regardless of the setting.
    public func canAutoApprove(_ action: ProposedAction) -> Bool {
        guard !action.isHighStakes else { return false }
        guard level(for: action.destinationID) == .autoWhenConfident else { return false }
        return action.confidence >= Self.autoApproveThreshold
    }
}
