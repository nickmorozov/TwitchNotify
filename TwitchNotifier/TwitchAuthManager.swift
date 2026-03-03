import Foundation
import Cocoa

final class TwitchAuthManager {
    static let shared = TwitchAuthManager()
    private var timeoutWork: DispatchWorkItem?
    var onAuthComplete: ((Bool) -> Void)?

    private init() {}

    /// The effective Client ID: Keychain override, then hardcoded default.
    var clientId: String? {
        if let saved = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
           !saved.isEmpty {
            return saved
        }
        let builtin = TwitchConstants.defaultClientId
        return builtin.isEmpty ? nil : builtin
    }

    func startAuth() {
        guard let clientId = clientId else { return }
        KeychainHelper.shared.save(clientId, forKey: "twitch_client_id")

        let redirectURI = TwitchConstants.redirectURI
        let authURL = "\(TwitchConstants.authURL)?client_id=\(clientId)"
            + "&redirect_uri=\(redirectURI)"
            + "&response_type=token"
            + "&scope=user:read:follows+user:read:subscriptions"
        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        }

        let timeout = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.onAuthComplete?(false) }
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
    }

    /// Called by AppDelegate when the custom URL scheme callback is received.
    func handleCallback(url: URL) {
        timeoutWork?.cancel()
        timeoutWork = nil

        // Twitch implicit grant puts token in the URL fragment:
        // twitchnotifier://callback#access_token=TOKEN&...
        guard let fragment = url.fragment else {
            DispatchQueue.main.async { self.onAuthComplete?(false) }
            return
        }

        let params = fragment.split(separator: "&").reduce(into: [String: String]()) { dict, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                dict[String(parts[0])] = String(parts[1])
            }
        }

        if let token = params["access_token"], !token.isEmpty {
            KeychainHelper.shared.save(token, forKey: "twitch_access_token")
            DispatchQueue.main.async { self.onAuthComplete?(true) }
        } else {
            DispatchQueue.main.async { self.onAuthComplete?(false) }
        }
    }

    func disconnect() {
        KeychainHelper.shared.delete(forKey: "twitch_access_token")
        KeychainHelper.shared.delete(forKey: "twitch_client_id")
    }

    var isAuthenticated: Bool {
        return KeychainHelper.shared.retrieve(forKey: "twitch_access_token") != nil
            && KeychainHelper.shared.retrieve(forKey: "twitch_client_id") != nil
    }
}
