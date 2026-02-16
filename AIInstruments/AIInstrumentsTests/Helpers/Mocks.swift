import Foundation
@testable import AIInstruments

// MARK: - Mock App Bundle Loader

struct MockAppBundleLoader: AppBundleLoading {
    let result: Result<AppBundle, Error>

    init(appBundle: AppBundle) {
        self.result = .success(appBundle)
    }

    init(error: Error) {
        self.result = .failure(error)
    }

    func load(from url: URL) async throws -> AppBundle {
        try result.get()
    }
}

// MARK: - Mock MachO Parser Service

struct MockMachOParserService: MachOParsing {
    let info: MachOInfo

    func parse(data: Data) -> MachOInfo {
        info
    }
}
