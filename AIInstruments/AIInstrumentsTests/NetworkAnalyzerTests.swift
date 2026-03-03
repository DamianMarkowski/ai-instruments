import Testing
import Nimble
@testable import AIInstruments

@Suite("NetworkAnalyzer Tests")
struct NetworkAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing empty binary produces no issues and perfect score")
    func emptyBinary() {
        let ba = makeBinaryAnalyzer()
        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()

        expect(result.instrument).to(equal(.network))
        expect(result.issues).to(beEmpty())
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Transport Security Detection

    @Test("Detects plaintext HTTP URLs")
    func plaintextHTTP() {
        let ba = makeBinaryAnalyzer(
            extractedStrings: [
                "http://api.example.com/data",
                "http://cdn.example.com/images",
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let atsIssues = result.issues.filter { $0.category == "Transport Security" }
        expect(atsIssues).toNot(beEmpty())
    }

    @Test("No transport security issue with HTTPS-only URLs")
    func httpsOnly() {
        let ba = makeBinaryAnalyzer(
            extractedStrings: [
                "https://api.example.com/data",
                "https://cdn.example.com/images",
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let atsIssues = result.issues.filter { $0.category == "Transport Security" }
        expect(atsIssues).to(beEmpty())
    }

    // MARK: - Certificate Pinning Detection

    @Test("Detects missing certificate pinning")
    func noCertificatePinning() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession_1"),
                makeSymbol("_dataTask_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_dataTask_2"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let pinIssues = result.issues.filter { $0.category == "Certificate Pinning" }
        expect(pinIssues).toNot(beEmpty())
    }

    @Test("No pinning issue when authentication challenges are handled")
    func withCertificatePinning() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession_1"),
                makeSymbol("_dataTask_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_dataTask_2"),
                makeSymbol("_URLAuthenticationChallenge"),
                makeSymbol("_serverTrust"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let pinIssues = result.issues.filter { $0.category == "Certificate Pinning" }
        expect(pinIssues).to(beEmpty())
    }

    // MARK: - Network Caching Detection

    @Test("Detects missing network response caching")
    func noNetworkCaching() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_dataTask_1"),
                makeSymbol("_dataTask_2"),
                makeSymbol("_URLSession_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_URLSession_3"),
                makeSymbol("_dataTask_3"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let cacheIssues = result.issues.filter { $0.category == "Network Caching" }
        expect(cacheIssues).toNot(beEmpty())
    }

    // MARK: - Third-Party Networking Detection

    @Test("Detects multiple networking frameworks")
    func multipleNetworkingFrameworks() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_Alamofire_request"),
                makeSymbol("_AFNetworking_manager"),
                makeSymbol("_AFHTTPSessionManager"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let frameworkIssues = result.issues.filter { $0.category == "Third-Party Networking" }
        expect(frameworkIssues).toNot(beEmpty())
    }

    @Test("Detects legacy AFNetworking alongside Alamofire")
    func legacyAFNetworking() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_Alamofire_session"),
                makeSymbol("_AFNetworking_ref"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let legacyIssues = result.issues.filter { $0.title.contains("Legacy AFNetworking") }
        expect(legacyIssues).toNot(beEmpty())
    }

    // MARK: - WebSocket Detection

    @Test("Detects WebSocket without heartbeat")
    func webSocketNoHeartbeat() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_URLSessionWebSocketTask")]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let wsIssues = result.issues.filter { $0.category == "WebSocket" }
        expect(wsIssues).toNot(beEmpty())
    }

    // MARK: - Data Serialization Detection

    @Test("Detects heavy JSON serialization")
    func heavyJsonSerialization() {
        var symbols: [SymbolInfo] = []
        for i in 0..<8 {
            symbols.append(makeSymbol("_JSONDecoder_\(i)"))
        }
        for i in 0..<5 {
            symbols.append(makeSymbol("_JSONEncoder_\(i)"))
        }

        let ba = makeBinaryAnalyzer(symbols: symbols)
        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let jsonIssues = result.issues.filter { $0.category == "Data Serialization" }
        expect(jsonIssues).toNot(beEmpty())
    }

    // MARK: - Session Configuration Detection

    @Test("Detects exclusive use of shared URLSession")
    func sharedSessionOnly() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_URLSession_3"),
                makeSymbol("_URLSession_4"),
                makeSymbol("_URLSession_5"),
                makeSymbol("_URLSession.shared_ref"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let sessionIssues = result.issues.filter { $0.category == "Session Configuration" }
        expect(sessionIssues).toNot(beEmpty())
    }

    // MARK: - Background Transfer Detection

    @Test("Detects large transfers without background sessions")
    func noBackgroundSessions() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_downloadTask_1"),
                makeSymbol("_downloadTask_2"),
                makeSymbol("_uploadTask_1"),
                makeSymbol("_uploadTask_2"),
            ]
        )

        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        let bgIssues = result.issues.filter { $0.category == "Background Transfers" }
        expect(bgIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more severe issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = NetworkAnalyzer(binaryAnalyzer: cleanBa).analyze()
        expect(cleanResult.score).to(equal(100))

        let dirtyBa = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_dataTask_1"),
                makeSymbol("_dataTask_2"),
                makeSymbol("_Alamofire_req"),
                makeSymbol("_AFNetworking_ref"),
            ],
            extractedStrings: [
                "http://insecure.api.com/data",
                "http://insecure.api.com/images",
            ]
        )
        let dirtyResult = NetworkAnalyzer(binaryAnalyzer: dirtyBa).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = NetworkAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["urlSessionPatterns"]).toNot(beNil())
        expect(result.metadata["networkFrameworks"]).toNot(beNil())
        expect(result.metadata["totalNetworkAPIs"]).toNot(beNil())
    }
}
