import Foundation

struct TwitchConstants {
    // Register your Twitch app at https://dev.twitch.tv/console/apps
    // Set the OAuth Redirect URL to http://localhost:8910/callback
    static let defaultClientId = ""  // TODO: paste your Twitch Client ID here

    static let helixStreamsURL = "https://api.twitch.tv/helix/streams"
    static let authURL = "https://id.twitch.tv/oauth2/authorize"
    static let helixUsersURL = "https://api.twitch.tv/helix/users"
    static let helixFollowedURL = "https://api.twitch.tv/helix/channels/followed"
    static let helixSubscriptionURL = "https://api.twitch.tv/helix/subscriptions/user"
    static let callbackPort: UInt16 = 8910
}
