import XCTest
@testable import SiftCore
@testable import Sift

/// The gate in front of person notes. Same stakes as the profile matcher, with a
/// harder job: third-person speech is looser than "remember that I…", so a false
/// match writes into a page the user curates about someone they know.
final class ObsidianPersonIntentTests: XCTestCase {

    func testMentionedRewritesNaturally() {
        let match = ObsidianPersonIntent.match(in: "Sarah mentioned she's moving to Austin in the spring")
        XCTAssertEqual(match?.name, "Sarah")
        XCTAssertEqual(match?.fact, "Mentioned that she's moving to Austin in the spring")
    }

    func testToldMeKeepsItsOwnShape() {
        let match = ObsidianPersonIntent.match(in: "Jordan told me the lease ends in June.")
        XCTAssertEqual(match?.name, "Jordan")
        XCTAssertEqual(match?.fact, "Told me the lease ends in June")
    }

    func testExplicitThatIsNotDoubled() {
        // "said that X" and "said X" must produce the same fact.
        let with = ObsidianPersonIntent.match(in: "Dana said that the beta went well overall")
        let without = ObsidianPersonIntent.match(in: "Dana said the beta went well overall")
        XCTAssertEqual(with?.fact, "Said that the beta went well overall")
        XCTAssertEqual(with?.fact, without?.fact)
    }

    func testTalkedToAboutBecomesTalkedAbout() {
        let match = ObsidianPersonIntent.match(in: "Talked to Priya about the hiring plan")
        XCTAssertEqual(match?.name, "Priya")
        XCTAssertEqual(match?.fact, "Talked about the hiring plan")
    }

    func testMetWithKeepsMet() {
        let match = ObsidianPersonIntent.match(in: "I met with Marcus about the lease renewal")
        XCTAssertEqual(match?.name, "Marcus")
        XCTAssertEqual(match?.fact, "Met about the lease renewal")
    }

    /// The failure that would hurt: pronouns and sentence-starters that look
    /// like names. Capitalization alone can't tell "She" from "Sarah".
    func testPronounsAreNotPeople() {
        XCTAssertNil(ObsidianPersonIntent.match(in: "She mentioned the office is moving downtown"))
        XCTAssertNil(ObsidianPersonIntent.match(in: "They told me the store closed last week"))
        XCTAssertNil(ObsidianPersonIntent.match(in: "Somebody said the wifi password changed"))
    }

    func testWeekdaysAreNotPeople() {
        XCTAssertNil(ObsidianPersonIntent.match(in: "Monday said it would rain all day"))
    }

    func testOrdinaryMemosDoNotMatch() {
        XCTAssertNil(ObsidianPersonIntent.match(in: "Remind me to call the dentist"))
        XCTAssertNil(ObsidianPersonIntent.match(in: "Had a great workout this morning"))
        XCTAssertNil(ObsidianPersonIntent.match(in: "Remember that I work best in the mornings"))
        XCTAssertNil(ObsidianPersonIntent.match(in: ""))
    }

    func testRemindersWearingATellingVerbAreRejected() {
        XCTAssertNil(ObsidianPersonIntent.match(in: "Sarah said remind me to send the invoice"))
    }
}

/// Person memos when no vault is connected: they must degrade into ordinary
/// notes, never into someone else's destination.
final class ObsidianPersonRoutingTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await ObsidianVault.shared.disconnect()
    }

    func testPersonMemoFallsBackToNoteWithoutAVault() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Sarah mentioned she's moving to Austin in the spring")
        let proposed = await router.propose(entry, CategorizationResult(category: .note, confidence: 0.9))
        XCTAssertEqual(proposed.first?.destinationID, "note",
                       "Person destination should decline when disconnected")
    }

    /// Even a *create* into a person note defaults to asking first — the
    /// destination's default trust level is alwaysAsk, unlike other creates.
    @MainActor
    func testPersonNotesDefaultToAlwaysAsk() {
        XCTAssertEqual(TrustSettings.defaultLevel(for: "obsidian.person"), .alwaysAsk)
        XCTAssertEqual(TrustSettings.defaultLevel(for: "obsidian"), .autoWhenConfident)
    }
}

/// Settings stored by an older build must survive new fields being added — a
/// user's configured folders shouldn't reset on update.
final class ObsidianSettingsMigrationTests: XCTestCase {
    func testOldSettingsJSONDecodesWithNewDefaults() throws {
        let old = """
        {"folder":"Inbox","profileNoteName":"Me","profileHeading":"Captured",
         "linkToExistingNotes":false,"profileCaptureEnabled":false}
        """
        let decoded = try JSONDecoder().decode(ObsidianSettings.self, from: Data(old.utf8))

        // Old values preserved…
        XCTAssertEqual(decoded.folder, "Inbox")
        XCTAssertEqual(decoded.profileNoteName, "Me")
        XCTAssertFalse(decoded.linkToExistingNotes)
        // …new fields get their defaults.
        XCTAssertTrue(decoded.peopleCaptureEnabled)
        XCTAssertEqual(decoded.peopleFolder, "People")
    }
}

// MARK: - Account

final class UserAccountTests: XCTestCase {
    func testInitialsFromName() {
        let account = UserAccount(providerUserID: "x", provider: .apple, displayName: "Sarah Chen")
        XCTAssertEqual(account.initials, "SC")
    }

    func testInitialsFallBackThroughEmail() {
        let account = UserAccount(providerUserID: "x", provider: .google, email: "jordan@example.com")
        XCTAssertEqual(account.initials, "J")
        XCTAssertEqual(account.displayTitle, "jordan@example.com")
    }

    /// Apple only shares name/email on the first authorization — a nameless
    /// account still needs something presentable.
    func testNamelessAccountStillPresents() {
        let account = UserAccount(providerUserID: "x", provider: .apple)
        XCTAssertEqual(account.initials, "•")
        XCTAssertEqual(account.displayTitle, "Apple account")
    }

    func testCodableRoundTrip() throws {
        let account = UserAccount(providerUserID: "abc123", provider: .google,
                                  displayName: "Ada Lovelace", email: "ada@example.com")
        let decoded = try JSONDecoder().decode(UserAccount.self,
                                               from: JSONEncoder().encode(account))
        XCTAssertEqual(decoded, account)
    }
}

/// The id_token parsing path — the part of Google sign-in that runs before any
/// UI and can be tested without a browser.
final class GoogleIdentityParsingTests: XCTestCase {
    /// Builds a structurally valid JWT with the given payload. The signature is
    /// junk, which is fine: Sift reads claims, it doesn't verify (there's no
    /// server session to protect — see the comment on `account(fromIDToken:)`).
    private func fakeJWT(payload: [String: String]) throws -> String {
        func segment(_ object: Any) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return try "\(segment(["alg": "RS256"])).\(segment(payload)).junksignature"
    }

    func testClaimsBecomeAnAccount() throws {
        let token = try fakeJWT(payload: ["sub": "108234", "email": "ada@example.com", "name": "Ada Lovelace"])
        let account = try GoogleIdentity.account(fromIDToken: token)
        XCTAssertEqual(account.provider, .google)
        XCTAssertEqual(account.providerUserID, "108234")
        XCTAssertEqual(account.displayName, "Ada Lovelace")
        XCTAssertEqual(account.email, "ada@example.com")
    }

    func testMissingOptionalClaimsAreTolerated() throws {
        let token = try fakeJWT(payload: ["sub": "108234"])
        let account = try GoogleIdentity.account(fromIDToken: token)
        XCTAssertEqual(account.providerUserID, "108234")
        XCTAssertNil(account.email)
    }

    func testMalformedTokenThrows() {
        XCTAssertThrowsError(try GoogleIdentity.account(fromIDToken: "not-a-jwt"))
    }

    func testBase64URLDecodingHandlesMissingPadding() {
        // "ab" encodes to "YWI" in base64url (padding stripped).
        XCTAssertEqual(GoogleIdentity.base64URLDecode("YWI").map { String(decoding: $0, as: UTF8.self) }, "ab")
    }
}

/// The weight-unit preference flows into extraction as the *fallback* — spoken
/// units always win.
final class HealthPreferencesTests: XCTestCase {
    func testPreferredUnitIsTheFallbackAndSpeechWins() {
        let original = HealthPreferences.defaultWeightUnit
        defer { HealthPreferences.defaultWeightUnit = original }

        HealthPreferences.defaultWeightUnit = .kilograms
        let bare = SetExtractor.extract(from: "squat 100 for 5")
        XCTAssertEqual(bare.first?.sets.first?.unit, .kilograms)

        let spoken = SetExtractor.extract(from: "squat 225 pounds for 5")
        XCTAssertEqual(spoken.first?.sets.first?.unit, .pounds)
    }
}
