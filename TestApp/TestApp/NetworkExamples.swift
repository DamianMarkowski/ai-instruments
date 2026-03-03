import UIKit
import Foundation

// =============================================================================
// MARK: - Network Issue Examples
//
// This file contains intentional networking anti-patterns that AIInstruments
// should detect when analyzing the compiled binary.
// =============================================================================

// MARK: - 1. Plaintext HTTP URLs

final class InsecureNetworkClient {
    let httpEndpoints = [
        "http://api.example.com/v1/users",
        "http://cdn.example.com/images/banner.png",
        "http://legacy.example.com/feed.json",
    ]

    func fetchInsecure() {
        for endpoint in httpEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
        }
    }
}

// MARK: - 2. Exclusive Shared URLSession Usage

final class SharedSessionOnlyClient {
    func fetchUsers() {
        let url = URL(string: "https://api.example.com/users")!
        URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
    }

    func fetchImages() {
        let url = URL(string: "https://cdn.example.com/images")!
        URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
    }

    func uploadData() {
        let url = URL(string: "https://api.example.com/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.uploadTask(with: request, from: Data()) { _, _, _ in }.resume()
    }

    func downloadFile() {
        let url = URL(string: "https://api.example.com/file")!
        URLSession.shared.downloadTask(with: url) { _, _, _ in }.resume()
    }
}

// MARK: - 3. No Certificate Pinning

final class UnpinnedNetworkClient {
    func fetchSensitiveData() {
        let url = URL(string: "https://api.example.com/account")!
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            _ = try? JSONSerialization.jsonObject(with: data)
        }
        task.resume()
    }
}

// MARK: - 4. Multiple Networking Frameworks

import class Foundation.URLSession

final class MixedNetworkingClient {
    func doRequest() {
        let url = URL(string: "https://api.example.com/data")!
        URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
    }
}

// MARK: - 5. WebSocket Without Heartbeat

final class SimpleWebSocketClient {
    var webSocketTask: URLSessionWebSocketTask?

    func connect() {
        let url = URL(string: "wss://ws.example.com/stream")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    func receiveMessage() {
        webSocketTask?.receive { result in
            switch result {
            case .success(let message):
                _ = message
                self.receiveMessage()
            case .failure:
                break
            }
        }
    }
}

// MARK: - 6. Heavy JSON Serialization

final class HeavyJSONProcessor {
    struct User: Codable {
        let id: Int
        let name: String
        let email: String
    }

    func processJSON(data: Data) {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        if let users = try? decoder.decode([User].self, from: data) {
            _ = try? encoder.encode(users)
        }

        _ = try? JSONSerialization.jsonObject(with: data)
        _ = try? JSONSerialization.data(withJSONObject: ["key": "value"])
    }
}
