import Foundation
import Cocoa

final class TwitchAuthManager {
    static let shared = TwitchAuthManager()
    private var serverSocket: Int32 = -1
    private var isRunning = false
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
        startServer()

        let redirectURI = "http://localhost:\(TwitchConstants.callbackPort)/callback"
        let authURL = "\(TwitchConstants.authURL)?client_id=\(clientId)"
            + "&redirect_uri=\(redirectURI)"
            + "&response_type=token"
            + "&scope=user:read:follows+user:read:subscriptions"
        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.stopServer()
            DispatchQueue.main.async { self?.onAuthComplete?(false) }
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
    }

    func disconnect() {
        KeychainHelper.shared.delete(forKey: "twitch_access_token")
        KeychainHelper.shared.delete(forKey: "twitch_client_id")
    }

    var isAuthenticated: Bool {
        return KeychainHelper.shared.retrieve(forKey: "twitch_access_token") != nil
            && KeychainHelper.shared.retrieve(forKey: "twitch_client_id") != nil
    }

    // MARK: - Local HTTP Server

    private func startServer() {
        guard !isRunning else { return }
        isRunning = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            self.serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard self.serverSocket >= 0 else {
                self.isRunning = false
                return
            }

            var reuse: Int32 = 1
            setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse,
                       socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(TwitchConstants.callbackPort).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(self.serverSocket, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult >= 0 else {
                Darwin.close(self.serverSocket)
                self.isRunning = false
                return
            }

            listen(self.serverSocket, 5)

            while self.isRunning {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        accept(self.serverSocket, sa, &clientLen)
                    }
                }
                guard clientSocket >= 0, self.isRunning else { break }
                self.handleClient(clientSocket)
            }
        }
    }

    private func stopServer() {
        isRunning = false
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
        timeoutWork?.cancel()
        timeoutWork = nil
    }

    private func handleClient(_ clientSocket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            Darwin.close(clientSocket)
            return
        }

        let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

        if requestString.hasPrefix("GET /callback") {
            let html = callbackHTML
            let response = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: text/html\r\n"
                + "Content-Length: \(html.utf8.count)\r\n"
                + "Connection: close\r\n\r\n"
                + html
            sendResponse(response, to: clientSocket)

        } else if requestString.hasPrefix("POST /token") {
            if let bodyStart = requestString.range(of: "\r\n\r\n") {
                let body = String(requestString[bodyStart.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    KeychainHelper.shared.save(body, forKey: "twitch_access_token")
                    let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n"
                        + "Connection: close\r\n\r\nOK"
                    sendResponse(response, to: clientSocket)
                    stopServer()
                    DispatchQueue.main.async { self.onAuthComplete?(true) }
                    return
                }
            }
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 5\r\n"
                + "Connection: close\r\n\r\nError"
            sendResponse(response, to: clientSocket)

        } else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n"
                + "Connection: close\r\n\r\nNot Found"
            sendResponse(response, to: clientSocket)
        }
    }

    private func sendResponse(_ response: String, to socket: Int32) {
        response.withCString { ptr in
            send(socket, ptr, Int(strlen(ptr)), 0)
        }
        Darwin.close(socket)
    }

    // The callback page uses safe DOM methods (createElement/textContent)
    // instead of innerHTML to avoid XSS concerns.
    private var callbackHTML: String {
        return """
        <!DOCTYPE html>
        <html><head><title>Twitch Notifier</title>
        <style>
        body { font-family: -apple-system, sans-serif; display: flex;
               justify-content: center; align-items: center; height: 100vh;
               margin: 0; background: #0e0e10; color: #efeff1; }
        .container { text-align: center; }
        h2 { color: #9147ff; }
        </style></head>
        <body><div class="container"><h2 id="title">Connecting...</h2>
        <p id="subtitle"></p></div>
        <script>
        var hash = window.location.hash.substring(1);
        var params = new URLSearchParams(hash);
        var token = params.get('access_token');
        if (token) {
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '/token', true);
            xhr.onload = function() {
                document.getElementById('title').textContent = 'Connected!';
                document.getElementById('subtitle').textContent =
                    'You can close this tab and return to the app.';
            };
            xhr.send(token);
        } else {
            document.getElementById('title').textContent = 'Authentication failed';
            document.getElementById('subtitle').textContent =
                'Please try again from the app.';
        }
        </script></body></html>
        """
    }
}
