import Foundation

/// Represents a loaded iOS application bundle ready for analysis.
struct AppBundle {
    let url: URL
    let name: String
    let bundleIdentifier: String
    let version: String
    let buildNumber: String
    let executableName: String
    let executableData: Data
    let minimumOSVersion: String
    let linkedFrameworks: [String]
    let infoPlist: [String: Any]
    let isEncrypted: Bool

    /// Loads an app bundle from a .app directory.
    static func load(from url: URL) async throws -> AppBundle {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "app":
            return try await loadFromAppBundle(url: url)
        default:
            throw AppBundleError.unsupportedFormat(ext)
        }
    }

    // MARK: - .app Bundle Loading

    private static func loadFromAppBundle(url: URL) async throws -> AppBundle {
        let infoPlistURL = url.appendingPathComponent("Info.plist")

        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw AppBundleError.missingInfoPlist
        }

        let plistData = try Data(contentsOf: infoPlistURL)
        guard let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            format: nil
        ) as? [String: Any] else {
            throw AppBundleError.invalidInfoPlist
        }

        let executableName = plist["CFBundleExecutable"] as? String ?? url.deletingPathExtension().lastPathComponent
        let executableURL = url.appendingPathComponent(executableName)

        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw AppBundleError.missingExecutable(executableName)
        }

        let executableData = try Data(contentsOf: executableURL)

        // Extract linked frameworks from Frameworks directory
        var frameworks: [String] = []
        let frameworksDir = url.appendingPathComponent("Frameworks")
        if FileManager.default.fileExists(atPath: frameworksDir.path) {
            let frameworkContents = try? FileManager.default.contentsOfDirectory(
                at: frameworksDir,
                includingPropertiesForKeys: nil
            )
            frameworks = frameworkContents?
                .filter { $0.pathExtension == "framework" || $0.pathExtension == "dylib" }
                .map { $0.deletingPathExtension().lastPathComponent } ?? []
        }

        let appName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        return AppBundle(
            url: url,
            name: appName,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String ?? "Unknown",
            version: plist["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: plist["CFBundleVersion"] as? String ?? "Unknown",
            executableName: executableName,
            executableData: executableData,
            minimumOSVersion: plist["MinimumOSVersion"] as? String ?? "Unknown",
            linkedFrameworks: frameworks,
            infoPlist: plist,
            isEncrypted: false // Will be determined by MachO parser
        )
    }
}

// MARK: - Errors

enum AppBundleError: LocalizedError {
    case unsupportedFormat(String)
    case missingInfoPlist
    case invalidInfoPlist
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext). Please provide an .app bundle."
        case .missingInfoPlist:
            return "The app bundle is missing its Info.plist file."
        case .invalidInfoPlist:
            return "The Info.plist file is invalid or corrupted."
        case .missingExecutable(let name):
            return "The executable '\(name)' was not found in the app bundle."
        }
    }
}
