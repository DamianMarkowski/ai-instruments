import Foundation
import Testing
import Nimble
import FactoryKit
import FactoryTesting
@testable import AIInstruments

@Suite("AnalysisEngine Tests", .serialized)
@MainActor
struct AnalysisEngineTests {

    // MARK: - Initial State

    @Test("Engine starts in idle state with no data")
    func initialState() {
        let engine = AnalysisEngine()
        expect(engine.state).to(equal(.idle))
        expect(engine.progress).to(equal(0))
        expect(engine.progressMessage).to(beEmpty())
        expect(engine.report).to(beNil())
        expect(engine.loadedApp).to(beNil())
        expect(engine.machOInfo).to(beNil())
        expect(engine.hasReport).to(beFalse())
    }

    // MARK: - Reset

    @Test("Reset clears all published state")
    func reset() {
        let engine = AnalysisEngine()
        engine.progress = 0.75
        engine.progressMessage = "Analyzing..."

        engine.reset()

        expect(engine.state).to(equal(.idle))
        expect(engine.progress).to(equal(0))
        expect(engine.progressMessage).to(beEmpty())
        expect(engine.report).to(beNil())
        expect(engine.loadedApp).to(beNil())
        expect(engine.machOInfo).to(beNil())
    }

    // MARK: - Result Accessor

    @Test("result(for:) returns nil when no report exists")
    func resultForNoReport() {
        let engine = AnalysisEngine()
        expect(engine.result(for: .leaks)).to(beNil())
        expect(engine.result(for: .concurrency)).to(beNil())
        expect(engine.result(for: .allocations)).to(beNil())
        expect(engine.result(for: .energy)).to(beNil())
        expect(engine.result(for: .network)).to(beNil())
        expect(engine.result(for: .hangs)).to(beNil())
        expect(engine.result(for: .startup)).to(beNil())
        expect(engine.result(for: .diskIO)).to(beNil())
    }

    // MARK: - State Equality

    @Test("State enum equality works correctly")
    func stateEquality() {
        expect(AnalysisEngine.State.idle == .idle).to(beTrue())
        expect(AnalysisEngine.State.loading == .loading).to(beTrue())
        expect(AnalysisEngine.State.parsing == .parsing).to(beTrue())
        expect(AnalysisEngine.State.complete == .complete).to(beTrue())
        expect(AnalysisEngine.State.error(message: "A") == .error(message: "A")).to(beTrue())
        expect(AnalysisEngine.State.error(message: "A") == .error(message: "B")).to(beFalse())
        expect(AnalysisEngine.State.analyzing(instrument: .leaks) == .analyzing(instrument: .leaks)).to(beTrue())
        expect(AnalysisEngine.State.analyzing(instrument: .leaks) == .analyzing(instrument: .concurrency)).to(beFalse())
        expect(AnalysisEngine.State.idle == .loading).to(beFalse())
    }

    // MARK: - Analysis with Mocked Dependencies

    @Test("Successful analysis produces complete report with all instruments")
    func successfulAnalysis() async {
        let mockBundle = makeAppBundle(name: "MockApp", bundleIdentifier: "com.mock.app")
        Container.shared.appBundleLoader.register { MockAppBundleLoader(appBundle: mockBundle) }

        let validInfo = MachOInfoBuilder().build()
        Container.shared.machOParser.register { MockMachOParserService(info: validInfo) }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/MockApp.app"))

        expect(engine.state).to(equal(.complete))
        expect(engine.hasReport).to(beTrue())
        expect(engine.report).toNot(beNil())
        expect(engine.report?.appName).to(equal("MockApp"))
        expect(engine.report?.bundleIdentifier).to(equal("com.mock.app"))
        expect(engine.report?.results.count).to(equal(8))
        expect(engine.loadedApp).toNot(beNil())
        expect(engine.machOInfo).toNot(beNil())
        expect(engine.progress).to(equal(1.0))

        Container.shared.reset()
    }

    @Test("Analysis error when app bundle loading fails")
    func appBundleLoadingError() async {
        Container.shared.appBundleLoader.register {
            MockAppBundleLoader(error: AppBundleError.missingInfoPlist)
        }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/Bad.app"))

        if case .error = engine.state {
            // Expected
        } else {
            Issue.record("Expected error state but got \(engine.state)")
        }
        expect(engine.report).to(beNil())

        Container.shared.reset()
    }

    @Test("Analysis error when binary is invalid")
    func invalidBinary() async {
        let mockBundle = makeAppBundle()
        Container.shared.appBundleLoader.register { MockAppBundleLoader(appBundle: mockBundle) }
        Container.shared.machOParser.register { MockMachOParserService(info: .invalid) }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/Test.app"))

        if case .error(let message) = engine.state {
            expect(message).to(contain("Failed to parse"))
        } else {
            Issue.record("Expected error state for invalid binary")
        }
        expect(engine.report).to(beNil())

        Container.shared.reset()
    }

    @Test("Analysis error when binary is encrypted")
    func encryptedBinary() async {
        let mockBundle = makeAppBundle()
        Container.shared.appBundleLoader.register { MockAppBundleLoader(appBundle: mockBundle) }

        var builder = MachOInfoBuilder()
        builder.isValid = false
        builder.isEncrypted = true
        Container.shared.machOParser.register { MockMachOParserService(info: builder.build()) }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/Test.app"))

        if case .error(let message) = engine.state {
            expect(message).to(contain("encrypted"))
        } else {
            Issue.record("Expected error state for encrypted binary")
        }

        Container.shared.reset()
    }

    @Test("Analysis merges additional binary data from debug dylibs")
    func mergesAdditionalBinaries() async {
        let mockBundle = makeAppBundle(
            additionalBinaryData: [Data([0x00, 0x01])]
        )
        Container.shared.appBundleLoader.register { MockAppBundleLoader(appBundle: mockBundle) }

        var mainBuilder = MachOInfoBuilder()
        mainBuilder.objcClasses = ["MainClass"]
        Container.shared.machOParser.register { MockMachOParserService(info: mainBuilder.build()) }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/Test.app"))

        expect(engine.state).to(equal(.complete))
        expect(engine.report).toNot(beNil())

        Container.shared.reset()
    }

    @Test("result(for:) returns correct instrument result after analysis")
    func resultForInstrument() async {
        let mockBundle = makeAppBundle()
        Container.shared.appBundleLoader.register { MockAppBundleLoader(appBundle: mockBundle) }
        Container.shared.machOParser.register { MockMachOParserService(info: MachOInfoBuilder().build()) }

        let engine = AnalysisEngine()
        await engine.analyze(url: URL(fileURLWithPath: "/tmp/Test.app"))

        expect(engine.result(for: .leaks)).toNot(beNil())
        expect(engine.result(for: .leaks)?.instrument).to(equal(.leaks))
        expect(engine.result(for: .concurrency)).toNot(beNil())
        expect(engine.result(for: .concurrency)?.instrument).to(equal(.concurrency))
        expect(engine.result(for: .allocations)).toNot(beNil())
        expect(engine.result(for: .allocations)?.instrument).to(equal(.allocations))
        expect(engine.result(for: .energy)).toNot(beNil())
        expect(engine.result(for: .energy)?.instrument).to(equal(.energy))
        expect(engine.result(for: .network)).toNot(beNil())
        expect(engine.result(for: .network)?.instrument).to(equal(.network))
        expect(engine.result(for: .hangs)).toNot(beNil())
        expect(engine.result(for: .hangs)?.instrument).to(equal(.hangs))
        expect(engine.result(for: .startup)).toNot(beNil())
        expect(engine.result(for: .startup)?.instrument).to(equal(.startup))
        expect(engine.result(for: .diskIO)).toNot(beNil())
        expect(engine.result(for: .diskIO)?.instrument).to(equal(.diskIO))

        Container.shared.reset()
    }
}
