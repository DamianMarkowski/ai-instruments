import Foundation
import FactoryTesting
@testable import AIInstruments

// MARK: - MachOInfo Builder

struct MachOInfoBuilder {
    var isValid = true
    var isFatBinary = false
    var isEncrypted = false
    var architecture = "arm64"
    var fileType = "Executable"
    var segments: [SegmentInfo] = []
    var symbols: [SymbolInfo] = []
    var linkedLibraries: [String] = []
    var extractedStrings: [String] = []
    var objcClasses: [String] = []
    var objcSelectors: [String] = []
    var objcProtocols: [String] = []
    var swiftTypeDescriptors: [String] = []
    var swiftProtocolConformances: [String] = []
    var sections: [SectionInfo] = []
    var totalTextSize: UInt64 = 0
    var totalDataSize: UInt64 = 0

    func build() -> MachOInfo {
        MachOInfo(
            isValid: isValid,
            isFatBinary: isFatBinary,
            isEncrypted: isEncrypted,
            architecture: architecture,
            fileType: fileType,
            segments: segments,
            symbols: symbols,
            linkedLibraries: linkedLibraries,
            extractedStrings: extractedStrings,
            objcClasses: objcClasses,
            objcSelectors: objcSelectors,
            objcProtocols: objcProtocols,
            swiftTypeDescriptors: swiftTypeDescriptors,
            swiftProtocolConformances: swiftProtocolConformances,
            sections: sections,
            totalTextSize: totalTextSize,
            totalDataSize: totalDataSize
        )
    }
}

// MARK: - Symbol Helper

func makeSymbol(
    _ name: String,
    isDefined: Bool = true,
    isExternal: Bool = true
) -> SymbolInfo {
    SymbolInfo(
        name: name,
        type: isDefined ? 0x0F : 0x01,
        sectionIndex: isDefined ? 1 : 0,
        flags: 0,
        value: 0,
        isExternal: isExternal,
        isUndefined: !isDefined,
        isDefined: isDefined,
        isDebug: false
    )
}

// MARK: - AppBundle Helper

func makeAppBundle(
    name: String = "TestApp",
    bundleIdentifier: String = "com.test.app",
    executableData: Data = Data(),
    additionalBinaryData: [Data] = []
) -> AppBundle {
    AppBundle(
        url: URL(fileURLWithPath: "/tmp/TestApp.app"),
        name: name,
        bundleIdentifier: bundleIdentifier,
        version: "1.0",
        buildNumber: "1",
        executableName: "TestApp",
        executableData: executableData,
        additionalBinaryData: additionalBinaryData,
        minimumOSVersion: "16.0",
        linkedFrameworks: [],
        infoPlist: [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name
        ],
        isEncrypted: false
    )
}

// MARK: - BinaryAnalyzer Convenience

func makeBinaryAnalyzer(
    symbols: [SymbolInfo] = [],
    objcClasses: [String] = [],
    objcSelectors: [String] = [],
    linkedLibraries: [String] = [],
    extractedStrings: [String] = [],
    swiftTypeDescriptors: [String] = [],
    swiftProtocolConformances: [String] = [],
    sections: [SectionInfo] = [],
    totalTextSize: UInt64 = 0,
    totalDataSize: UInt64 = 0
) -> BinaryAnalyzer {
    var builder = MachOInfoBuilder()
    builder.symbols = symbols
    builder.objcClasses = objcClasses
    builder.objcSelectors = objcSelectors
    builder.linkedLibraries = linkedLibraries
    builder.extractedStrings = extractedStrings
    builder.swiftTypeDescriptors = swiftTypeDescriptors
    builder.swiftProtocolConformances = swiftProtocolConformances
    builder.sections = sections
    builder.totalTextSize = totalTextSize
    builder.totalDataSize = totalDataSize
    return BinaryAnalyzer(machOInfo: builder.build())
}

// MARK: - Minimal Mach-O 64 Binary Data

func makeMinimalMachO64(
    cpuType: UInt32 = 0x0100000C,
    fileType: UInt32 = 0x02,
    ncmds: UInt32 = 0,
    sizeofcmds: UInt32 = 0
) -> Data {
    var data = Data()
    var magic: UInt32 = 0xFEEDFACF
    data.append(Data(bytes: &magic, count: 4))
    var cpu = cpuType
    data.append(Data(bytes: &cpu, count: 4))
    var cpuSub: UInt32 = 0
    data.append(Data(bytes: &cpuSub, count: 4))
    var ft = fileType
    data.append(Data(bytes: &ft, count: 4))
    var nc = ncmds
    data.append(Data(bytes: &nc, count: 4))
    var sc = sizeofcmds
    data.append(Data(bytes: &sc, count: 4))
    var flags: UInt32 = 0
    data.append(Data(bytes: &flags, count: 4))
    var reserved: UInt32 = 0
    data.append(Data(bytes: &reserved, count: 4))
    return data
}
