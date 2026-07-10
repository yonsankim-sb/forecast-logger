import Foundation

/// Lightweight, catalog-independent localization for strings produced in code
/// (view-model notices, `APIError` messages, idle prompts, dynamic labels).
///
/// The app forces its language via `AuthStore.languageCode`, so these strings
/// pick their variant from that same code rather than the system locale. Static
/// strings in SwiftUI `Text` keep using the String Catalog as before.
enum L {
    /// Returns `ja` when the language code is Japanese, otherwise `en`.
    static func s(_ en: String, _ ja: String, _ languageCode: String) -> String {
        languageCode == "ja" ? ja : en
    }
}

/// A transient, typed message shown in the app's inline banner. Success/info
/// notices auto-dismiss quickly; errors linger a little longer. Carries an
/// already-localized `message`.
struct Notice: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    var kind: Kind
    var message: String

    /// Seconds before the notice self-dismisses.
    var autoDismissAfter: TimeInterval {
        switch kind {
        case .error: return 7
        case .success, .info: return 4
        }
    }
}
