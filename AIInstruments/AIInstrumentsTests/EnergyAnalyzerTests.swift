import Testing
import Nimble
@testable import AIInstruments

@Suite("EnergyAnalyzer Tests")
struct EnergyAnalyzerTests {

    // MARK: - Basic Analysis

    @Test("Analyzing empty binary produces no issues and perfect score")
    func emptyBinary() {
        let ba = makeBinaryAnalyzer()
        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()

        expect(result.instrument).to(equal(.energy))
        expect(result.issues).to(beEmpty())
        expect(result.score).to(equal(100))
        expect(result.analysisTimeSeconds).to(beGreaterThanOrEqualTo(0))
    }

    // MARK: - Location Tracking Detection

    @Test("Detects continuous location without significant-change alternative")
    func continuousLocation() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_startUpdatingLocation"),
                makeSymbol("_CLLocationManager_init"),
            ],
            objcSelectors: ["startUpdatingLocation"]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let locationIssues = result.issues.filter { $0.category == "Location Tracking" }
        expect(locationIssues).toNot(beEmpty())
    }

    @Test("No continuous location issue when significant-change is used")
    func significantChangeLocation() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_startUpdatingLocation"),
                makeSymbol("_startMonitoringSignificantLocationChanges"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let continuousIssues = result.issues.filter {
            $0.category == "Location Tracking" && $0.title.contains("Continuous")
        }
        expect(continuousIssues).to(beEmpty())
    }

    @Test("Detects always-on location authorization")
    func alwaysLocationAuth() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_requestAlwaysAuthorization")]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let authIssues = result.issues.filter { $0.title.contains("Always-On") }
        expect(authIssues).toNot(beEmpty())
    }

    // MARK: - Timer Usage Detection

    @Test("Detects timers without tolerance configuration")
    func timersWithoutTolerance() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_scheduledTimer_1"),
                makeSymbol("_scheduledTimer_2"),
                makeSymbol("_NSTimer_1"),
                makeSymbol("_NSTimer_2"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let timerIssues = result.issues.filter { $0.category == "Timer Usage" }
        expect(timerIssues).toNot(beEmpty())
    }

    @Test("Detects CADisplayLink without frame rate limiting")
    func displayLinkNoFrameRate() {
        let ba = makeBinaryAnalyzer(
            symbols: [makeSymbol("_CADisplayLink_create")]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let displayLinkIssues = result.issues.filter { $0.title.contains("CADisplayLink") }
        expect(displayLinkIssues).toNot(beEmpty())
    }

    // MARK: - Background Processing Detection

    @Test("Detects extensive background processing")
    func extensiveBackgroundProcessing() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_beginBackgroundTask_1"),
                makeSymbol("_beginBackgroundTask_2"),
                makeSymbol("_BGTaskScheduler_1"),
                makeSymbol("_BGTaskScheduler_2"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let bgIssues = result.issues.filter { $0.category == "Background Processing" }
        expect(bgIssues).toNot(beEmpty())
    }

    // MARK: - Network Configuration Detection

    @Test("Detects network sessions without connectivity waiting")
    func networkNoWaitsForConnectivity() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_URLSession_1"),
                makeSymbol("_URLSession_2"),
                makeSymbol("_dataTask_1"),
                makeSymbol("_dataTask_2"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let netIssues = result.issues.filter { $0.category == "Network Configuration" }
        expect(netIssues).toNot(beEmpty())
    }

    // MARK: - Sensor Usage Detection

    @Test("Detects continuous motion sensor usage")
    func motionSensorUsage() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_CMMotionManager_1"),
                makeSymbol("_startAccelerometerUpdates"),
                makeSymbol("_CoreMotion_ref"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let sensorIssues = result.issues.filter { $0.category == "Sensor Usage" }
        expect(sensorIssues).toNot(beEmpty())
    }

    // MARK: - CPU Intensity Detection

    @Test("Detects significant CPU-intensive operations")
    func cpuIntensiveOps() {
        let ba = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_CryptoKit_1"),
                makeSymbol("_CryptoKit_2"),
                makeSymbol("_CoreML_1"),
                makeSymbol("_MLModel_1"),
                makeSymbol("_CIFilter_1"),
                makeSymbol("_CIContext_1"),
            ]
        )

        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        let cpuIssues = result.issues.filter { $0.category == "CPU Intensity" }
        expect(cpuIssues).toNot(beEmpty())
    }

    // MARK: - Scoring

    @Test("Score decreases with more severe issues")
    func scoringPenalty() {
        let cleanBa = makeBinaryAnalyzer()
        let cleanResult = EnergyAnalyzer(binaryAnalyzer: cleanBa).analyze()
        expect(cleanResult.score).to(equal(100))

        let dirtyBa = makeBinaryAnalyzer(
            symbols: [
                makeSymbol("_startUpdatingLocation"),
                makeSymbol("_CLLocationManager"),
                makeSymbol("_CADisplayLink_create"),
                makeSymbol("_beginBackgroundTask_1"),
                makeSymbol("_beginBackgroundTask_2"),
                makeSymbol("_beginBackgroundTask_3"),
                makeSymbol("_beginBackgroundTask_4"),
            ],
            objcSelectors: ["startUpdatingLocation"]
        )
        let dirtyResult = EnergyAnalyzer(binaryAnalyzer: dirtyBa).analyze()
        expect(dirtyResult.score).to(beLessThan(cleanResult.score))
    }

    // MARK: - Metadata

    @Test("Result metadata contains expected keys")
    func metadata() {
        let ba = makeBinaryAnalyzer()
        let result = EnergyAnalyzer(binaryAnalyzer: ba).analyze()
        expect(result.metadata["locationAPIs"]).toNot(beNil())
        expect(result.metadata["timerPatterns"]).toNot(beNil())
        expect(result.metadata["backgroundModes"]).toNot(beNil())
    }
}
