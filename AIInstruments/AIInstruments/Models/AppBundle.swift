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

    /// Loads an app bundle from a .app directory or .ipa file.
    static func load(from url: URL) async throws -> AppBundle {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "ipa":
            return try await loadFromIPA(url: url)
        case "app":
            return try await loadFromAppBundle(url: url)
        default:
            throw AppBundleError.unsupportedFormat(ext)
        }
    }

    // MARK: - IPA Loading

    private static func loadFromIPA(url: URL) async throws -> AppBundle {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("APD_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Extract IPA (which is a ZIP file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", url.path, tempDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // Fallback to unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", url.path, "-d", tempDir.path]
            unzipProcess.standardOutput = Pipe()
            unzipProcess.standardError = Pipe()

            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw AppBundleError.extractionFailed
            }

            return try await findAndLoadApp(in: tempDir)
        }

        return try await findAndLoadApp(in: tempDir)
    }

    private static func findAndLoadApp(in directory: URL) async throws -> AppBundle {
        let payloadDir = directory.appendingPathComponent("Payload")

        guard FileManager.default.fileExists(atPath: payloadDir.path) else {
            throw AppBundleError.invalidIPAStructure
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: payloadDir,
            includingPropertiesForKeys: nil
        )

        guard let appDir = contents.first(where: { $0.pathExtension == "app" }) else {
            throw AppBundleError.noAppBundleFound
        }

        return try await loadFromAppBundle(url: appDir)
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
    case extractionFailed
    case invalidIPAStructure
    case noAppBundleFound
    case missingInfoPlist
    case invalidInfoPlist
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext). Please provide a .ipa or .app bundle."
        case .extractionFailed:
            return "Failed to extract the IPA file. The file may be corrupted."
        case .invalidIPAStructure:
            return "Invalid IPA structure. No Payload directory found."
        case .noAppBundleFound:
            return "No .app bundle found inside the IPA Payload directory."
        case .missingInfoPlist:
            return "The app bundle is missing its Info.plist file."
        case .invalidInfoPlist:
            return "The Info.plist file is invalid or corrupted."
        case .missingExecutable(let name):
            return "The executable '\(name)' was not found in the app bundle."
        }
    }
}
