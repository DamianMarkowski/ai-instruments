import Foundation

/// Analyzes iOS app binaries for patterns that negatively impact battery life.
///
/// Detection categories:
/// - Continuous location tracking
/// - Excessive timer usage
/// - Background processing patterns
/// - Network session configuration
/// - Animation and display link overhead
/// - Sensor and Bluetooth usage
/// - Push notification patterns
/// - CPU-intensive patterns
final class EnergyAnalyzer {

    private let analyzer: BinaryAnalyzer

    init(binaryAnalyzer: BinaryAnalyzer) {
        self.analyzer = binaryAnalyzer
    }

    func analyze() -> AnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var issues: [DiagnosticIssue] = []

        issues.append(contentsOf: analyzeLocationTracking())
        issues.append(contentsOf: analyzeTimerUsage())
        issues.append(contentsOf: analyzeBackgroundProcessing())
        issues.append(contentsOf: analyzeNetworkConfiguration())
        issues.append(contentsOf: analyzeAnimationOverhead())
        issues.append(contentsOf: analyzeSensorUsage())
        issues.append(contentsOf: analyzePushNotifications())
        issues.append(contentsOf: analyzeCPUIntensivePatterns())

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let score = calculateScore(issues: issues)

        return AnalysisResult(
            instrument: .energy,
            issues: issues.sorted { $0.severity < $1.severity },
            summary: generateSummary(issues: issues, score: score),
            score: score,
            analysisTimeSeconds: elapsed,
            metadata: [
                "locationAPIs": "\(analyzer.countAllEvidence(matchingAny: ["CLLocationManager", "CoreLocation"]))",
                "timerPatterns": "\(analyzer.countAllEvidence(matchingAny: ["Timer", "NSTimer", "CADisplayLink"]))",
                "backgroundModes": "\(analyzer.countAllEvidence(matchingAny: ["beginBackgroundTask", "BGTaskScheduler"]))"
            ]
        )
    }

    // MARK: - Location Tracking Analysis

    private func analyzeLocationTracking() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let locationManagerCount = analyzer.countAllEvidence(matchingAny: [
            "CLLocationManager", "CoreLocation", "startUpdatingLocation",
            "requestAlwaysAuthorization", "requestWhenInUseAuthorization"
        ])

        let continuousLocationCount = analyzer.countAllEvidence(matchingAny: [
            "startUpdatingLocation", "allowsBackgroundLocationUpdates",
            "kCLLocationAccuracyBest", "kCLLocationAccuracyNearestTenMeters"
        ])

        let significantChangeCount = analyzer.countAllEvidence(matchingAny: [
            "startMonitoringSignificantLocationChanges",
            "significantLocationChange"
        ])

        let alwaysAuthCount = analyzer.countAllEvidence(matchingAny: [
            "requestAlwaysAuthorization", "NSLocationAlwaysUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription"
        ])

        if continuousLocationCount > 0 && significantChangeCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Continuous Location Without Significant-Change Alternative",
                description: "Found \(continuousLocationCount) continuous location tracking pattern(s) but no significant-change monitoring. Continuous GPS tracking is one of the highest battery drains on iOS.",
                severity: .warning,
                instrument: .energy,
                category: "Location Tracking",
                recommendation: "Use `startMonitoringSignificantLocationChanges()` instead of `startUpdatingLocation()` when precise, real-time location is not required. For navigation, use `desiredAccuracy = kCLLocationAccuracyHundredMeters` when high accuracy isn't needed.",
                impact: "Continuous GPS tracking can drain the battery by 5-10% per hour. Significant-change monitoring uses cell tower data and consumes negligible power.",
                confidence: analyzer.confidenceScore(evidenceCount: continuousLocationCount, lowThreshold: 1, highThreshold: 5),
                details: [
                    .init(key: "Continuous Location Patterns", value: "\(continuousLocationCount)"),
                    .init(key: "Significant-Change Patterns", value: "\(significantChangeCount)")
                ]
            ))
        }

        if alwaysAuthCount > 0 {
            issues.append(DiagnosticIssue(
                title: "Always-On Location Authorization Requested",
                description: "Found \(alwaysAuthCount) pattern(s) requesting Always location authorization. Always-on location access enables background GPS tracking which has significant battery impact.",
                severity: .info,
                instrument: .energy,
                category: "Location Tracking",
                recommendation: "Prefer When-In-Use location authorization unless background tracking is essential. If Always authorization is needed, use significant-change monitoring or visit monitoring instead of continuous updates in the background.",
                impact: "Always-on location authorization allows the app to use GPS in the background, significantly increasing battery consumption even when the user isn't actively using the app.",
                confidence: 0.7,
                details: [
                    .init(key: "Always-Auth Patterns", value: "\(alwaysAuthCount)"),
                    .init(key: "Total Location APIs", value: "\(locationManagerCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Timer Usage Analysis

    private func analyzeTimerUsage() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let timerCount = analyzer.countAllEvidence(matchingAny: [
            "scheduledTimer", "NSTimer", "timerWithTimeInterval",
            "Timer.publish"
        ])

        let displayLinkCount = analyzer.countAllEvidence(matchingAny: [
            "CADisplayLink", "displayLink"
        ])

        let timerToleranceCount = analyzer.countAllEvidence(matchingAny: [
            "tolerance", "setTolerance"
        ])

        if timerCount > 3 && timerToleranceCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Timers Without Tolerance Configuration",
                description: "Found \(timerCount) timer pattern(s) but no timer tolerance settings. Timer coalescing via tolerance allows the system to batch timer fires, reducing wake-ups.",
                severity: .info,
                instrument: .energy,
                category: "Timer Usage",
                recommendation: "Set `timer.tolerance` to at least 10% of the timer interval. This allows the OS to coalesce timer fires with other system events, reducing CPU wake-ups and battery drain.",
                impact: "Timers without tolerance force the CPU to wake up at exact intervals, preventing the CPU from entering low-power idle states between timer fires.",
                confidence: 0.55,
                details: [
                    .init(key: "Timer Patterns", value: "\(timerCount)"),
                    .init(key: "Tolerance Settings", value: "\(timerToleranceCount)")
                ]
            ))
        }

        if displayLinkCount > 0 {
            let preferredFrameRateCount = analyzer.countAllEvidence(matchingAny: [
                "preferredFrameRateRange", "preferredFramesPerSecond"
            ])

            if preferredFrameRateCount == 0 {
                issues.append(DiagnosticIssue(
                    title: "CADisplayLink Without Frame Rate Limiting",
                    description: "Found \(displayLinkCount) CADisplayLink usage(s) without frame rate configuration. Display links fire at the screen refresh rate (up to 120Hz on ProMotion devices).",
                    severity: .warning,
                    instrument: .energy,
                    category: "Timer Usage",
                    recommendation: "Set `preferredFrameRateRange` on CADisplayLink to limit updates to the minimum required rate. For non-animation UI updates, 30fps is often sufficient.",
                    impact: "An unrestricted CADisplayLink on a ProMotion display fires 120 times per second, consuming significant CPU and GPU resources even for simple updates.",
                    confidence: 0.65,
                    details: [
                        .init(key: "Display Link Patterns", value: "\(displayLinkCount)"),
                        .init(key: "Frame Rate Config", value: "\(preferredFrameRateCount)")
                    ]
                ))
            }
        }

        return issues
    }

    // MARK: - Background Processing Analysis

    private func analyzeBackgroundProcessing() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let bgTaskCount = analyzer.countAllEvidence(matchingAny: [
            "beginBackgroundTask", "UIBackgroundTaskIdentifier",
            "endBackgroundTask"
        ])

        let bgSchedulerCount = analyzer.countAllEvidence(matchingAny: [
            "BGTaskScheduler", "BGAppRefreshTaskRequest",
            "BGProcessingTaskRequest", "registerForTaskWithIdentifier"
        ])

        let bgFetchCount = analyzer.countAllEvidence(matchingAny: [
            "performFetchWithCompletionHandler",
            "setMinimumBackgroundFetchInterval"
        ])

        let totalBgPatterns = bgTaskCount + bgSchedulerCount + bgFetchCount

        if totalBgPatterns > 3 {
            issues.append(DiagnosticIssue(
                title: "Extensive Background Processing",
                description: "Found \(totalBgPatterns) background processing pattern(s). Excessive background work is a major source of battery drain and may be throttled by the system.",
                severity: .info,
                instrument: .energy,
                category: "Background Processing",
                recommendation: "Minimize background processing to essential tasks. Use `BGProcessingTaskRequest` for long-running tasks and `BGAppRefreshTaskRequest` for periodic updates. Complete background tasks promptly and call `endBackgroundTask` when done.",
                impact: "Background processing prevents the device from entering deep sleep, consuming battery even when the user isn't actively using the app.",
                confidence: analyzer.confidenceScore(evidenceCount: totalBgPatterns, lowThreshold: 2, highThreshold: 10),
                details: [
                    .init(key: "Background Tasks", value: "\(bgTaskCount)"),
                    .init(key: "BGTaskScheduler", value: "\(bgSchedulerCount)"),
                    .init(key: "Background Fetch", value: "\(bgFetchCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Network Configuration Analysis

    private func analyzeNetworkConfiguration() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let networkCount = analyzer.countAllEvidence(matchingAny: [
            "URLSession", "NSURLSession", "dataTask", "downloadTask",
            "uploadTask"
        ])

        let waitsForConnectivityCount = analyzer.countAllEvidence(matchingAny: [
            "waitsForConnectivity"
        ])

        let timeoutCount = analyzer.countAllEvidence(matchingAny: [
            "timeoutIntervalForResource", "timeoutIntervalForRequest"
        ])

        if networkCount > 3 && waitsForConnectivityCount == 0 {
            issues.append(DiagnosticIssue(
                title: "Network Sessions Without Connectivity Waiting",
                description: "Found \(networkCount) network session patterns but no `waitsForConnectivity` configuration. Without this, failed requests due to connectivity are retried immediately, wasting battery.",
                severity: .suggestion,
                instrument: .energy,
                category: "Network Configuration",
                recommendation: "Set `URLSessionConfiguration.waitsForConnectivity = true` to let the system wait for connectivity rather than failing immediately. This avoids wasteful retry loops on poor connections.",
                impact: "Repeated network retries when connectivity is poor drain battery through radio wake-ups without successfully completing requests.",
                confidence: 0.5,
                details: [
                    .init(key: "Network Session Patterns", value: "\(networkCount)"),
                    .init(key: "Waits For Connectivity", value: "\(waitsForConnectivityCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Animation Overhead Analysis

    private func analyzeAnimationOverhead() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let animationCount = analyzer.countAllEvidence(matchingAny: [
            "UIViewPropertyAnimator", "animateWithDuration",
            "CABasicAnimation", "CAKeyframeAnimation",
            "CATransition", "UIViewAnimationOptions"
        ])

        let particleCount = analyzer.countAllEvidence(matchingAny: [
            "CAEmitterLayer", "CAEmitterCell", "SCNParticleSystem",
            "SKEmitterNode"
        ])

        let metalCount = analyzer.countAllEvidence(matchingAny: [
            "MTLDevice", "MTLCommandQueue", "MTLRenderPipelineState",
            "Metal"
        ])

        let totalGPUIntensive = particleCount + metalCount

        if animationCount > 10 && totalGPUIntensive > 0 {
            issues.append(DiagnosticIssue(
                title: "Heavy Animation with GPU-Intensive Operations",
                description: "Found \(animationCount) animation patterns alongside \(totalGPUIntensive) GPU-intensive operations (particles, Metal). Continuous GPU load significantly impacts battery life.",
                severity: .warning,
                instrument: .energy,
                category: "Animation Overhead",
                recommendation: "Pause or reduce animations when the app is in the background or the device is in Low Power Mode. Use `ProcessInfo.processInfo.isLowPowerModeEnabled` to adapt animation complexity.",
                impact: "Continuous GPU-intensive rendering prevents the GPU from entering idle state, drawing significant power even for visually simple scenes.",
                confidence: 0.6,
                details: [
                    .init(key: "Animation Patterns", value: "\(animationCount)"),
                    .init(key: "Particle Systems", value: "\(particleCount)"),
                    .init(key: "Metal Operations", value: "\(metalCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - Sensor Usage Analysis

    private func analyzeSensorUsage() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let motionCount = analyzer.countAllEvidence(matchingAny: [
            "CMMotionManager", "startAccelerometerUpdates",
            "startGyroUpdates", "startDeviceMotionUpdates",
            "CoreMotion"
        ])

        let bluetoothCount = analyzer.countAllEvidence(matchingAny: [
            "CBCentralManager", "CBPeripheralManager",
            "CoreBluetooth", "scanForPeripherals"
        ])

        if motionCount > 2 {
            issues.append(DiagnosticIssue(
                title: "Continuous Motion Sensor Usage",
                description: "Found \(motionCount) Core Motion pattern(s). Continuous accelerometer/gyroscope updates prevent the motion coprocessor from handling these efficiently.",
                severity: .info,
                instrument: .energy,
                category: "Sensor Usage",
                recommendation: "Use the lowest acceptable sensor update interval. For step counting or activity detection, use `CMPedometer` or `CMMotionActivityManager` which leverage the low-power motion coprocessor.",
                impact: "Continuous motion sensor polling at high frequencies keeps the main processor active, consuming 2-5x more power than coprocessor-based motion detection.",
                confidence: 0.6,
                details: [
                    .init(key: "Motion Sensor Patterns", value: "\(motionCount)")
                ]
            ))
        }

        if bluetoothCount > 2 {
            let bgBluetoothCount = analyzer.countAllEvidence(matchingAny: [
                "bluetooth-central", "bluetooth-peripheral",
                "CBCentralManagerScanOptionAllowDuplicatesKey"
            ])

            if bgBluetoothCount > 0 {
                issues.append(DiagnosticIssue(
                    title: "Background Bluetooth Scanning",
                    description: "Found \(bluetoothCount) Bluetooth patterns with \(bgBluetoothCount) background-capable configuration(s). Background BLE scanning drains battery through continuous radio usage.",
                    severity: .warning,
                    instrument: .energy,
                    category: "Sensor Usage",
                    recommendation: "Avoid scanning with `CBCentralManagerScanOptionAllowDuplicatesKey` in the background. Limit scan duration and use service UUID filters to reduce radio activity.",
                    impact: "Background BLE scanning keeps the Bluetooth radio active continuously, consuming significant battery even when no devices are found.",
                    confidence: 0.65,
                    details: [
                        .init(key: "Bluetooth Patterns", value: "\(bluetoothCount)"),
                        .init(key: "Background BLE Config", value: "\(bgBluetoothCount)")
                    ]
                ))
            }
        }

        return issues
    }

    // MARK: - Push Notification Analysis

    private func analyzePushNotifications() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let pushCount = analyzer.countAllEvidence(matchingAny: [
            "registerForRemoteNotifications",
            "UNUserNotificationCenter",
            "didRegisterForRemoteNotificationsWithDeviceToken"
        ])

        let silentPushCount = analyzer.countAllEvidence(matchingAny: [
            "content-available", "didReceiveRemoteNotification:fetchCompletionHandler",
            "application:didReceiveRemoteNotification:fetchCompletionHandler"
        ])

        if silentPushCount > 1 {
            issues.append(DiagnosticIssue(
                title: "Silent Push Notification Usage",
                description: "Found \(silentPushCount) silent push notification pattern(s). Silent pushes wake the app to perform background work, which impacts battery life if used frequently.",
                severity: .suggestion,
                instrument: .energy,
                category: "Push Notifications",
                recommendation: "Limit silent push frequency to essential updates. iOS throttles silent pushes and may delay them under battery pressure. Complete background work quickly and call the completion handler promptly.",
                impact: "Each silent push wakes the app from suspension, activating the CPU, network, and potentially disk I/O. Frequent silent pushes prevent the device from staying in deep sleep.",
                confidence: 0.55,
                details: [
                    .init(key: "Push Notification APIs", value: "\(pushCount)"),
                    .init(key: "Silent Push Patterns", value: "\(silentPushCount)")
                ]
            ))
        }

        return issues
    }

    // MARK: - CPU-Intensive Pattern Analysis

    private func analyzeCPUIntensivePatterns() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        let cryptoCount = analyzer.countAllEvidence(matchingAny: [
            "CryptoKit", "CommonCrypto", "SecKey", "CC_SHA",
            "CC_MD5", "AES", "RSA"
        ])

        let mlCount = analyzer.countAllEvidence(matchingAny: [
            "CoreML", "MLModel", "VNCoreMLRequest",
            "NaturalLanguage", "CreateML"
        ])

        let imageProcessingCount = analyzer.countAllEvidence(matchingAny: [
            "CIFilter", "CIContext", "CoreImage",
            "vImage", "Accelerate"
        ])

        let totalCPUIntensive = cryptoCount + mlCount + imageProcessingCount

        if totalCPUIntensive > 5 {
            let qosCount = analyzer.countAllEvidence(matchingAny: [
                "qualityOfService", "QualityOfService",
                "userInitiated", "utility", "background"
            ])

            issues.append(DiagnosticIssue(
                title: "Significant CPU-Intensive Operations",
                description: "Found \(totalCPUIntensive) CPU-intensive operations (\(cryptoCount) crypto, \(mlCount) ML, \(imageProcessingCount) image processing). Heavy CPU work drains battery and generates heat.",
                severity: qosCount > 0 ? .info : .warning,
                instrument: .energy,
                category: "CPU Intensity",
                recommendation: "Schedule CPU-intensive work at `.utility` or `.background` QoS to allow the system to manage power efficiently. Defer non-urgent processing to when the device is charging using `ProcessInfo.processInfo.isLowPowerModeEnabled`.",
                impact: "CPU-intensive operations at high priority prevent the processor from throttling to lower power states, significantly increasing energy consumption and thermal output.",
                confidence: analyzer.confidenceScore(evidenceCount: totalCPUIntensive, lowThreshold: 3, highThreshold: 15),
                details: [
                    .init(key: "Crypto Operations", value: "\(cryptoCount)"),
                    .init(key: "ML Inferences", value: "\(mlCount)"),
                    .init(key: "Image Processing", value: "\(imageProcessingCount)"),
                    .init(key: "QoS Configuration", value: "\(qosCount)")
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
            return "No significant energy impact patterns detected. Your app appears to follow energy-efficient practices."
        }

        let critical = issues.filter { $0.severity == .critical }.count
        let warnings = issues.filter { $0.severity == .warning }.count

        if critical > 0 {
            return "Found \(critical) critical and \(warnings) warning-level energy impact pattern(s). These patterns significantly affect battery life and should be addressed immediately."
        } else if warnings > 0 {
            return "Found \(warnings) warning-level energy impact pattern(s) that may reduce battery life. Review recommended to optimize energy usage."
        } else {
            return "Found \(issues.count) energy-related finding(s). These are patterns worth reviewing to improve battery efficiency."
        }
    }
}
