import Foundation

/// Publisher, contact, and legal page details shown in About, Privacy, Account, and Help.
/// The support email here is a fallback; `AppModel.supportEmail` prefers the value `/app-info` returns.
/// The legal pages are shared with the Android app and the web dashboard, so they live on the website.
nonisolated enum EGuardPublisher {
    /// Used for both support and privacy questions, and for App Store review contact.
    static let supportEmail = "support@devcomdigital.com"
    static let name = "Devcom Digital Marketing Services"
    static let address = "Brgy. Hipusngo, Baybay City, Leyte 6521, Philippines"
    static let websiteURL = URL(string: "https://www.eguard.family")!
    /// Also entered in App Store Connect as the app's privacy policy URL.
    static let privacyPolicyURL = URL(string: "https://www.eguard.family/privacy")!
    static let termsURL = URL(string: "https://www.eguard.family/terms")!
    /// Account deletion happens on the web; the app links here so the process is reachable in-app.
    static let deleteAccountURL = URL(string: "https://www.eguard.family/delete-account")!

    /// The website without its scheme, for display.
    static var websiteLabel: String { websiteURL.host() ?? websiteURL.absoluteString }

    static func mailURL(for email: String) -> URL? {
        URL(string: "mailto:\(email)")
    }
}
