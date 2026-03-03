import Foundation

/// Analyzes iOS app binaries for networking patterns and potential issues.
///
/// Detection categories:
/// - URL session configuration
/// - App Transport Security compliance
/// - Certificate pinning
/// - Network caching strategy
/// - Background transfers
/// - Third-party networking frameworks
/// - WebSocket usage
/// - Data serialization efficiency
final class NetworkAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeURLSessionConfiguration())
        issues.append(contentsOf: analyzeTransportSecurity())
        issues.append(contentsOf: analyzeCertificatePinning())
        issues.append(contentsOf: analyzeNetworkCaching())
        issues.append(contentsOf: analyzeBackgroundTransfers())
        issues.append(contentsOf: analyzeThirdPartyNetworking())
        issues.append(contentsOf: analyzeWebSocketUsage())
        issues.append(contentsOf: analyzeDataSerialization())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .network,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "urlSessionPatterns": "\(analyzer.countAllEvidence(matchingAny: ["URLSession", "NSURLSession"]))",
                "networkFrameworks": "\(analyzer.countAllEvidence(matchingAny: ["Alamofire", "AFNetworking", "Moya"]))",
                "totalNetworkAPIs": "\(analyzer.countAllEvidence(matchingAny: ["dataTask", "downloadTask", "uploadTask", "URLRequest"]))"
            ]
        )
    }

    // MARK: - URL Session Configuration Analysis

    private func analyzeURLSessionConfiguration() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let sessionCount = analyzer.countAllEvidence(matchingAny: [
            "URLSession", "NSURLSession"
        ])

        let sharedSessionCount = analyzer.countAllEvidence(matchingAny: [
            "URLSession.shared", "sharedSession"
        ])

        let customConfigCount = analyzer.countAllEvidence(matchingAny: [
            "URLSessionConfiguration", "defaultSessionConfiguration",
            "ephemeralSessionConfiguration"
        ])

        if sessionCount > 5 && customConfigCount == 0 && sharedSessionCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Exclusive Use of Shared URLSession",
                description: "Found \(sessionCount) URLSession references all using the shared session with no custom configuration. The shared session has limited customization for caching, timeouts, and connection pooling.",
                severity: .info,
                instrument: .network,
                category: "Session Configuration",
                recommendation: "Create custom `URLSessionConfiguration` instances for different networking needs (e.g., API calls vs. image downloads). This allows fine-tuning of cache policies, timeout intervals, and connection limits per use case.",
                impact: "Using only the shared session means all network requests share the same configuration, making it impossible to optimize settings for different request types.",
                confidence: 0.55,
                details: [
                    .init(key: "URLSession References", value: "\(sessionCount)"),
                    .init(key: "Shared Session Uses", value: "\(sharedSessionCount)"),
                    .init(key: "Custom Configurations", value: "\(customConfigCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - App Transport Security Analysis

    private func analyzeTransportSecurity() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let httpStrings = analyzer.findStrings(matching: "http://")
        let nsExceptionStrings = analyzer.findStrings(matching: "NSAppTransportSecurity")
        let arbitraryLoadsStrings = analyzer.findStrings(matching: "NSAllowsArbitraryLoads")

        if !httpStrings.isEmpty {
            let httpOnlyCount = httpStrings.count

            issues.append(DiagnosticIssue(
                title: "Plaintext HTTP URLs Detected",
                description: "Found \(httpOnlyCount) plaintext HTTP URL(s) in the binary. HTTP connections transmit data unencrypted and are blocked by ATS by default.",
                severity: httpOnlyCount > 5 ? .warning : .info,
                instrument: .network,
                category: "Transport Security",
                recommendation: "Migrate all URLs to HTTPS. If HTTP is required for specific domains, use ATS exception domains in Info.plist rather than disabling ATS globally with `NSAllowsArbitraryLoads`.",
                impact: "Plaintext HTTP connections expose user data to interception via man-in-the-middle attacks. App Store review may reject apps that disable ATS without justification.",
                confidence: analyzer.confidenceScore(evidenceCount: httpOnlyCount, lowThreshold: 1, highThreshold: 10),
                relatedSymbols: Array(httpStrings.prefix(5)),
                details: [
                    .init(key: "HTTP URLs", value: "\(httpOnlyCount)"),
                    .init(key: "ATS Config Strings", value: "\(nsExceptionStrings.count)"),
                    .init(key: "Arbitrary Loads", value: "\(arbitraryLoadsStrings.count)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Certificate Pinning Analysis

    private func analyzeCertificatePinning() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let networkCount = analyzer.countAllEvidence(matchingAny: [
            "URLSession", "dataTask", "downloadTask"
        ])

        let pinningCount = analyzer.countAllEvidence(matchingAny: [
            "URLAuthenticationChallenge", "didReceiveChallenge",
            "serverTrust", "SecTrustEvaluate", "SecTrustCopyPublicKey",
            "TrustKit", "CertificatePinning", "pinnedCertificates"
        ])

        let authDelegateCount = analyzer.countAllEvidence(matchingAny: [
            "urlSession:didReceiveChallenge:completionHandler:",
            "URLSessionDelegate"
        ])

        if networkCount > 3 && pinningCount == 0 {
            issues.append(DiagnosticIssue(
                title: "No Certificate Pinning Detected",
                description: "Found \(networkCount) network operations but no certificate pinning implementation. Certificate pinning prevents man-in-the-middle attacks even when a CA is compromised.",
                severity: .suggestion,
                instrument: .network,
                category: "Certificate Pinning",
                recommendation: "Implement certificate or public key pinning for sensitive API connections using `URLSessionDelegate`'s `didReceiveChallenge` method or a library like TrustKit. Pin to backup certificates to avoid lockout during rotation.",
                impact: "Without certificate pinning, network traffic can be intercepted by anyone with a trusted CA certificate installed on the device, including enterprise MDM profiles.",
                confidence: 0.45,
                details: [
                    .init(key: "Network Operations", value: "\(networkCount)"),
                    .init(key: "Pinning Patterns", value: "\(pinningCount)"),
                    .init(key: "Auth Delegates", value: "\(authDelegateCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Network Caching Analysis

    private func analyzeNetworkCaching() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let networkCount = analyzer.countAllEvidence(matchingAny: [
            "dataTask", "URLSession"
        ])

        let cacheCount = analyzer.countAllEvidence(matchingAny: [
            "URLCache", "CachedURLResponse", "NSURLCache",
            "requestCachePolicy", "cachePolicy"
        ])

        let etagCount = analyzer.countAllEvidence(matchingAny: [
            "If-None-Match", "ETag", "If-Modified-Since",
            "Last-Modified", "304"
        ])

        if networkCount > 5 && cacheCount == 0 && etagCount == 0 {
            issues.append(DiagnosticIssue(
                title: "No Network Response Caching Detected",
                description: "Found \(networkCount) network operations but no URL caching or conditional request patterns. Without caching, identical responses are re-downloaded on every request.",
                severity: .info,
                instrument: .network,
                category: "Network Caching",
                recommendation: "Configure `URLCache` with appropriate memory and disk capacity. Use HTTP caching headers (ETag, Cache-Control) to enable conditional requests that return 304 Not Modified when content hasn't changed.",
                impact: "Without caching, the app downloads the same data repeatedly, wasting bandwidth and battery. Proper caching can reduce network traffic by 40-60% for typical apps.",
                confidence: 0.5,
                details: [
                    .init(key: "Network Operations", value: "\(networkCount)"),
                    .init(key: "Cache Patterns", value: "\(cacheCount)"),
                    .init(key: "Conditional Requests", value: "\(etagCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Background Transfer Analysis

    private func analyzeBackgroundTransfers() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let downloadTaskCount = analyzer.countAllEvidence(matchingAny: [
            "downloadTask", "uploadTask"
        ])

        let bgSessionCount = analyzer.countAllEvidence(matchingAny: [
            "backgroundSessionConfiguration",
            "background(withIdentifier:",
            "isDiscretionary"
        ])

        if downloadTaskCount > 3 && bgSessionCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Large Transfers Without Background Sessions",
                description: "Found \(downloadTaskCount) download/upload task(s) but no background session configuration. Large transfers that start in the foreground will fail if the user leaves the app.",
                severity: .suggestion,
                instrument: .network,
                category: "Background Transfers",
                recommendation: "Use `URLSessionConfiguration.background(withIdentifier:)` for large file downloads and uploads. Background sessions continue transfers even when the app is suspended and can be made discretionary for non-urgent transfers.",
                impact: "Foreground-only transfers are cancelled when the app is backgrounded, forcing the user to re-download content. Background sessions also enable system-optimized scheduling.",
                confidence: 0.5,
                details: [
                    .init(key: "Download/Upload Tasks", value: "\(downloadTaskCount)"),
                    .init(key: "Background Sessions", value: "\(bgSessionCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Third-Party Networking Analysis

    private func analyzeThirdPartyNetworking() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let alamofireCount = analyzer.countAllEvidence(matchingAny: [
            "Alamofire", "AF."
        ])

        let afNetworkingCount = analyzer.countAllEvidence(matchingAny: [
            "AFNetworking", "AFHTTPSessionManager", "AFURLSessionManager"
        ])

        let moyaCount = analyzer.countAllEvidence(matchingAny: [
            "MoyaProvider", "Moya"
        ])

        let nativeCount = analyzer.countAllEvidence(matchingAny: [
            "URLSession", "dataTask"
        ])

        var frameworks: [String] = []
        if alamofireCount > 0 { frameworks.append("Alamofire") }
        if afNetworkingCount > 0 { frameworks.append("AFNetworking") }
        if moyaCount > 0 { frameworks.append("Moya") }

        if frameworks.count > 1 {
            issues.append(DiagnosticIssue(
                title: "Multiple Networking Frameworks Detected",
                description: "Found \(frameworks.count) networking frameworks (\(frameworks.joined(separator: ", "))). Using multiple networking libraries increases binary size and makes network behavior harder to audit.",
                severity: .info,
                instrument: .network,
                category: "Third-Party Networking",
                recommendation: "Consolidate to a single networking framework. If using Swift, consider migrating to native URLSession with async/await, which has first-class support and no third-party dependency overhead.",
                impact: "Multiple networking frameworks increase binary size, may have conflicting caching/retry policies, and make it harder to implement consistent logging, authentication, and error handling.",
                confidence: 0.7,
                relatedSymbols: frameworks,
                details: [
                    .init(key: "Frameworks Found", value: frameworks.joined(separator: ", ")),
                    .init(key: "Native URLSession", value: "\(nativeCount)")
                ]
            ))
        }

        if afNetworkingCount > 0 && alamofireCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Legacy AFNetworking Alongside Alamofire",
                description: "Both AFNetworking (Objective-C) and Alamofire (Swift) are linked. AFNetworking is largely superseded by Alamofire and native URLSession.",
                severity: .suggestion,
                instrument: .network,
                category: "Third-Party Networking",
                recommendation: "Migrate from AFNetworking to Alamofire or native URLSession. AFNetworking is in maintenance mode and does not support Swift concurrency.",
                impact: "Carrying both libraries adds unnecessary binary size and introduces two separate request pipelines that may behave differently.",
                confidence: 0.75
            ))
        }

        return issues
    }

    // MARK: - WebSocket Analysis

    private func analyzeWebSocketUsage() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let webSocketCount = analyzer.countAllEvidence(matchingAny: [
            "URLSessionWebSocketTask", "webSocketTask",
            "Starscream", "SocketIO", "WebSocket"
        ])

        let heartbeatCount = analyzer.countAllEvidence(matchingAny: [
            "ping", "pong", "heartbeat", "keepAlive"
        ])

        if webSocketCount > 0 && heartbeatCount == 0 {
            issues.append(DiagnosticIssue(
                title: "WebSocket Without Heartbeat Mechanism",
                description: "Found \(webSocketCount) WebSocket pattern(s) but no ping/pong or heartbeat handling. WebSocket connections without heartbeats may silently disconnect.",
                severity: .suggestion,
                instrument: .network,
                category: "WebSocket",
                recommendation: "Implement periodic ping/pong frames to detect stale connections. Use `URLSessionWebSocketTask.sendPing` or implement application-level heartbeats. Handle reconnection gracefully.",
                impact: "WebSocket connections without heartbeats can appear connected while actually being dead, leading to missed messages and degraded user experience.",
                confidence: 0.5,
                details: [
                    .init(key: "WebSocket Patterns", value: "\(webSocketCount)"),
                    .init(key: "Heartbeat Patterns", value: "\(heartbeatCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Data Serialization Analysis

    private func analyzeDataSerialization() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let jsonCount = analyzer.countAllEvidence(matchingAny: [
            "JSONDecoder", "JSONEncoder", "JSONSerialization",
            "jsonObject"
        ])

        let codableCount = analyzer.countAllEvidence(matchingAny: [
            "Codable", "Decodable", "Encodable", "CodingKey"
        ])

        let protobufCount = analyzer.countAllEvidence(matchingAny: [
            "protobuf", "SwiftProtobuf", "GPBMessage"
        ])

        if jsonCount > 10 && protobufCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Heavy JSON Serialization",
                description: "Found \(jsonCount) JSON serialization patterns. JSON is human-readable but less efficient than binary formats for high-frequency or large-payload transfers.",
                severity: .suggestion,
                instrument: .network,
                category: "Data Serialization",
                recommendation: "For high-frequency API calls or large payloads, consider binary formats like Protocol Buffers or MessagePack. For JSON, ensure you use `Codable` with `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` to avoid manual key mapping overhead.",
                impact: "JSON parsing is CPU-intensive for large payloads and the text format uses 2-5x more bandwidth than equivalent binary formats like Protocol Buffers.",
                confidence: 0.4,
                details: [
                    .init(key: "JSON Operations", value: "\(jsonCount)"),
                    .init(key: "Codable Patterns", value: "\(codableCount)"),
                    .init(key: "Binary Formats", value: "\(protobufCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Scoring

    private func calculateScore(issues: [DiagnosticIssue]) -> Int {
        let totalPenalty = issues.reduce(0) { $0 + $1.severity.weight }
        return max(0, 100 - totalPenalty)
    }

    private func generateSummary(issues: [DiagnosticIssue], score: Int) -> String {
        if issues.isEmpty {
            return "No significant networking issues detected. Your app appears to follow good networking practices."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level networking issue(s). These patterns may expose user data or cause network failures."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level networking pattern(s) that may affect security or performance. Review recommended."
        } else {
            return "Found \(issues.count) networking finding(s). These are patterns worth reviewing to improve network efficiency and security."
        }
    }
}
