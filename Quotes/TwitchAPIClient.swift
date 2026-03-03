import Foundation

enum StreamStatus {
    case live(title: String)
    case offline
    case error(String)
    case unauthorized
}

final class TwitchAPIClient {
    static let shared = TwitchAPIClient()
    private init() {}

    func checkStream(username: String, completion: @escaping (StreamStatus) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion(.unauthorized) }
            return
        }

        let urlString = "\(TwitchConstants.helixStreamsURL)?user_login=\(username)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(.error("Invalid username")) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.error(error.localizedDescription)) }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                DispatchQueue.main.async { completion(.unauthorized) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.error("No data received")) }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArray = json["data"] as? [[String: Any]] else {
                    DispatchQueue.main.async { completion(.error("Invalid response")) }
                    return
                }

                if let stream = dataArray.first,
                   let title = stream["title"] as? String {
                    DispatchQueue.main.async { completion(.live(title: title)) }
                } else {
                    DispatchQueue.main.async { completion(.offline) }
                }
            } catch {
                DispatchQueue.main.async { completion(.error(error.localizedDescription)) }
            }
        }.resume()
    }

    func checkStreams(usernames: [String], completion: @escaping ([String: StreamStatus]) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion([:]) }
            return
        }
        guard !usernames.isEmpty else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        let queryItems = usernames.map { "user_login=\($0)" }.joined(separator: "&")
        let urlString = "\(TwitchConstants.helixStreamsURL)?\(queryItems)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([:]) }
                return
            }

            var results: [String: StreamStatus] = [:]
            for name in usernames {
                results[name.lowercased()] = .offline
            }
            for stream in dataArray {
                if let login = stream["user_login"] as? String,
                   let title = stream["title"] as? String {
                    results[login.lowercased()] = .live(title: title)
                }
            }
            DispatchQueue.main.async { completion(results) }
        }.resume()
    }

    /// Fetches broadcaster IDs for a list of logins. Needed for subscription checks.
    func fetchUserIds(logins: [String], completion: @escaping ([String: String]) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion([:]) }
            return
        }
        guard !logins.isEmpty else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        let query = logins.map { "login=\($0)" }.joined(separator: "&")
        let urlString = "\(TwitchConstants.helixUsersURL)?\(query)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let users = json["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            var map: [String: String] = [:]
            for user in users {
                if let login = user["login"] as? String,
                   let id = user["id"] as? String {
                    map[login.lowercased()] = id
                }
            }
            DispatchQueue.main.async { completion(map) }
        }.resume()
    }

    /// Checks subscription status for a single broadcaster.
    /// Returns true if the authenticated user is subscribed to the broadcaster.
    func checkSubscription(broadcasterId: String, completion: @escaping (Bool) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let urlString = "\(TwitchConstants.helixSubscriptionURL)?broadcaster_id=\(broadcasterId)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]],
                  !dataArray.isEmpty else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async { completion(true) }
        }.resume()
    }

    /// Checks subscription status for multiple broadcasters, calling back with
    /// a set of logins that the user is subscribed to.
    func checkSubscriptions(logins: [String], broadcasterIds: [String: String],
                            completion: @escaping (Set<String>) -> Void) {
        guard !logins.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let group = DispatchGroup()
        var subscribed = Set<String>()
        let lock = NSLock()

        for login in logins {
            guard let broadcasterId = broadcasterIds[login.lowercased()] else { continue }
            group.enter()
            checkSubscription(broadcasterId: broadcasterId) { isSub in
                if isSub {
                    lock.lock()
                    subscribed.insert(login.lowercased())
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(subscribed)
        }
    }

    func fetchFollowedChannels(completion: @escaping ([String]) -> Void) {
        guard let clientId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id"),
              let token = KeychainHelper.shared.retrieve(forKey: "twitch_access_token") else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        guard let usersURL = URL(string: TwitchConstants.helixUsersURL) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var userReq = URLRequest(url: usersURL)
        userReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        userReq.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: userReq) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let users = json["data"] as? [[String: Any]],
                  let userId = users.first?["id"] as? String else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self?.fetchAllFollowed(userId: userId, clientId: clientId, token: token,
                                   accumulated: [], cursor: nil, completion: completion)
        }.resume()
    }

    private func fetchAllFollowed(userId: String, clientId: String, token: String,
                                  accumulated: [String], cursor: String?,
                                  completion: @escaping ([String]) -> Void) {
        var urlString = "\(TwitchConstants.helixFollowedURL)?user_id=\(userId)&first=100"
        if let cursor = cursor {
            urlString += "&after=\(cursor)"
        }
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(accumulated) }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(accumulated) }
                return
            }

            let names = dataArray.compactMap { $0["broadcaster_login"] as? String }
            let all = accumulated + names

            if let pagination = json["pagination"] as? [String: Any],
               let nextCursor = pagination["cursor"] as? String,
               !names.isEmpty {
                self?.fetchAllFollowed(userId: userId, clientId: clientId, token: token,
                                      accumulated: all, cursor: nextCursor, completion: completion)
            } else {
                DispatchQueue.main.async { completion(all) }
            }
        }.resume()
    }
}
