import Foundation

/// The signed-in identity, if the user chose to have one.
///
/// **What an account is *not*, in Sift:** a gate. There is no Sift server — the
/// journal, health log, and vault access all live on the device, and every
/// feature works signed out. An account attaches a name to the data and gives a
/// future sync/backup story a seam to plug into, which is why it's optional and
/// why nothing checks for it before doing work.
public struct UserAccount: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, Sendable {
        case apple
        case google

        public var displayName: String {
            switch self {
            case .apple:  return "Apple"
            case .google: return "Google"
            }
        }
    }

    /// The provider's stable identifier for this user (Apple's opaque user ID,
    /// Google's `sub` claim). Not shown in UI; used to detect re-sign-ins.
    public let providerUserID: String
    public let provider: Provider
    /// Nil when the provider withheld it — Apple only shares the name on the
    /// *first* authorization, so a re-sign-in after data loss arrives nameless.
    public var displayName: String?
    public var email: String?
    public let createdAt: Date

    public init(providerUserID: String, provider: Provider,
                displayName: String? = nil, email: String? = nil,
                createdAt: Date = Date()) {
        self.providerUserID = providerUserID
        self.provider = provider
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
    }

    /// "Sarah Chen" → "SC", for the avatar tile. Falls back through email to
    /// the provider mark so there's always something to draw.
    public var initials: String {
        if let displayName, !displayName.isEmpty {
            let parts = displayName.split(separator: " ").prefix(2)
            let letters = parts.compactMap(\.first).map(String.init).joined()
            if !letters.isEmpty { return letters.uppercased() }
        }
        if let first = email?.first { return String(first).uppercased() }
        return "•"
    }

    /// What the profile card leads with.
    public var displayTitle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return "\(provider.displayName) account"
    }
}

/// Small, durable preferences that aren't worth a settings screen of their own.
/// Static UserDefaults access so value-type destinations can read them without
/// plumbing a store through the router.
public enum HealthPreferences {
    private static let unitKey = "sift.health.weightUnit"

    /// The unit assumed when a memo doesn't say — "squat 100 for 5" means kg to
    /// a lifter who thinks in kg. Speech that names a unit always wins.
    public static var defaultWeightUnit: WeightUnit {
        get {
            UserDefaults.standard.string(forKey: unitKey)
                .flatMap(WeightUnit.init(rawValue:)) ?? .pounds
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: unitKey)
        }
    }
}
