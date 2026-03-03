import Foundation

struct TwitchConstants {
    // Injected at build time via Secrets.xcconfig → Info.plist
    static let defaultClientId: String = {
        Bundle.main.object(forInfoDictionaryKey: "TwitchClientId") as? String ?? ""
    }()

    static let helixStreamsURL = "https://api.twitch.tv/helix/streams"
    static let authURL = "https://id.twitch.tv/oauth2/authorize"
    static let helixUsersURL = "https://api.twitch.tv/helix/users"
    static let helixFollowedURL = "https://api.twitch.tv/helix/channels/followed"
    static let helixSubscriptionURL = "https://api.twitch.tv/helix/subscriptions/user"
    static let redirectURI = "https://enum-solutions-inc.github.io/twitch-notifier/callback"
}
