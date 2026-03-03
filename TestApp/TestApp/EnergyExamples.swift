import UIKit
import CoreLocation
import CoreMotion
import CoreBluetooth
import Foundation

// =============================================================================
// MARK: - Energy Impact Examples
//
// This file contains intentional energy-draining patterns that AIInstruments
// should detect when analyzing the compiled binary.
// =============================================================================

// MARK: - 1. Continuous Location Tracking

final class ContinuousLocationTracker: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()

    func startTracking() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        _ = location.coordinate
    }
}

// MARK: - 2. Excessive Timers Without Tolerance

final class ExcessiveTimerUsage {
    var timers: [Timer] = []

    func startTimers() {
        for _ in 0..<5 {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                _ = Date()
            }
            timers.append(timer)
        }
    }
}

// MARK: - 3. CADisplayLink Without Frame Rate Limiting

final class UnlimitedDisplayLink {
    var displayLink: CADisplayLink?

    func start() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc func tick() {
        _ = CACurrentMediaTime()
    }
}

// MARK: - 4. Background Processing

final class HeavyBackgroundWorker {
    func doBackgroundWork() {
        let taskId = UIApplication.shared.beginBackgroundTask {
        }

        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 25)
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}

// MARK: - 5. Motion Sensors

final class ContinuousMotionTracker {
    let motionManager = CMMotionManager()

    func startTracking() {
        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let data = data else { return }
            _ = data.acceleration
        }
        motionManager.startGyroUpdates(to: .main) { data, _ in
            guard let data = data else { return }
            _ = data.rotationRate
        }
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion = motion else { return }
            _ = motion.attitude
        }
    }
}

// MARK: - 6. CPU-Intensive Operations

final class CPUIntensiveProcessor {
    func processData() {
        let data = Data(repeating: 0xFF, count: 10_000_000)
        _ = data.base64EncodedString()
        _ = data.base64EncodedData()
    }
}
