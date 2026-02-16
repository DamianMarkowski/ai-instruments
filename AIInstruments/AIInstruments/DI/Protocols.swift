import Foundation

/// Protocol for loading app bundles, enabling dependency injection and testing.
protocol AppBundleLoading {
    func load(from url: URL) async throws -> AppBundle
}

/// Protocol for parsing Mach-O binary data, enabling dependency injection and testing.
protocol MachOParsing {
    func parse(data: Data) -> MachOInfo
}

// MARK: - Default Implementations

struct DefaultAppBundleLoader: AppBundleLoading {
    func load(from url: URL) async throws -> AppBundle {
        try await AppBundle.load(from: url)
    }
}

struct DefaultMachOParserService: MachOParsing {
    func parse(data: Data) -> MachOInfo {
        MachOParser(data: data).parse()
    }
}
