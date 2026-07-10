import Foundation
import Combine

/// Holds authentication state: the Harvest account id (in UserDefaults) and the
/// personal access token (in the Keychain). Published so views react to
/// connect/disconnect.
@MainActor
final class AuthStore: ObservableObject {
    private enum Keys {
        static let accountId = "harvest.accountId"
        static let contactEmail = "harvest.contactEmail"
        static let language = "app.language"
    }

    /// UI language code: "en" or "ja".
    @Published var languageCode: String {
        didSet { UserDefaults.standard.set(languageCode, forKey: Keys.language) }
    }

    /// Locale used to drive SwiftUI string localization.
    var locale: Locale { Locale(identifier: languageCode) }

    /// Account id, e.g. `123456`. Read from settings — never hardcoded.
    @Published var accountId: String {
        didSet { UserDefaults.standard.set(accountId, forKey: Keys.accountId) }
    }

    /// Contact email placed in the `User-Agent` header per Harvest's guidance.
    @Published var contactEmail: String {
        didSet { UserDefaults.standard.set(contactEmail, forKey: Keys.contactEmail) }
    }

    /// The token, backed by the Keychain. Never persisted to UserDefaults.
    @Published private(set) var token: String?

    init() {
        let defaults = UserDefaults.standard
        accountId = defaults.string(forKey: Keys.accountId) ?? ""
        contactEmail = defaults.string(forKey: Keys.contactEmail) ?? ""
        token = KeychainStore.loadToken()
        // Default to Japanese if the system prefers it, else English.
        if let saved = defaults.string(forKey: Keys.language) {
            languageCode = saved
        } else {
            languageCode = (Locale.preferredLanguages.first?.hasPrefix("ja") == true) ? "ja" : "en"
        }
    }

    /// True when we have both a token and an account id — enough to make calls.
    var isConfigured: Bool {
        guard let token, !token.isEmpty else { return false }
        return !accountId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Persist the token to the Keychain and update published state.
    func setToken(_ newToken: String) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.saveToken(trimmed)
        token = trimmed.isEmpty ? nil : trimmed
    }

    /// Forget the token and clear published state.
    func clearToken() {
        KeychainStore.deleteToken()
        token = nil
    }

    /// Build the credentials snapshot the API client needs, or nil if not ready.
    func credentials() -> APICredentials? {
        guard let token, !token.isEmpty else { return nil }
        let account = accountId.trimmingCharacters(in: .whitespaces)
        guard !account.isEmpty else { return nil }
        let email = contactEmail.trimmingCharacters(in: .whitespaces)
        return APICredentials(
            token: token,
            accountId: account,
            contactEmail: email.isEmpty ? "user@example.com" : email
        )
    }
}

#if DEBUG
extension AuthStore {
    /// A configured (or not) store for SwiftUI previews — no Keychain/network.
    static func preview(configured: Bool = true, language: String = "ja") -> AuthStore {
        let store = AuthStore()
        store.accountId = configured ? "123456" : ""
        store.contactEmail = "you@example.com"
        store.languageCode = language
        store.token = configured ? "preview-token" : nil
        return store
    }
}
#endif
