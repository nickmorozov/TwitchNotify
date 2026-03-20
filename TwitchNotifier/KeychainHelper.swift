import Foundation

/// Stores app tokens in UserDefaults (sandboxed to the app container).
/// The OAuth bearer token is not a user credential — UserDefaults is
/// appropriate here and avoids keychain ACL password prompts entirely.
final class KeychainHelper {
    static let shared = KeychainHelper()
    private let defaults = UserDefaults.standard
    private let prefix = "nwapp.TwitchNotifier."

    private init() {}

    func save(_ value: String, forKey key: String) {
        defaults.set(value, forKey: prefix + key)
    }

    func retrieve(forKey key: String) -> String? {
        defaults.string(forKey: prefix + key)
    }

    func delete(forKey key: String) {
        defaults.removeObject(forKey: prefix + key)
    }
}
