import FactoryKit

extension Container {
    var appBundleLoader: Factory<any AppBundleLoading> {
        self { DefaultAppBundleLoader() }
    }

    var machOParser: Factory<any MachOParsing> {
        self { DefaultMachOParserService() }
    }
}
