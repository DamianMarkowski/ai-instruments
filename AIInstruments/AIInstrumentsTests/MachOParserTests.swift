import Foundation
import Testing
import Nimble
@testable import AIInstruments

@Suite("MachOParser Tests")
struct MachOParserTests {

    @Test("Parsing empty data returns invalid")
    func emptyData() {
        let parser = MachOParser(data: Data())
        let info = parser.parse()
        expect(info.isValid).to(beFalse())
    }

    @Test("Parsing data smaller than 4 bytes returns invalid")
    func tooSmallData() {
        let parser = MachOParser(data: Data([0x01, 0x02, 0x03]))
        let info = parser.parse()
        expect(info.isValid).to(beFalse())
    }

    @Test("Parsing data with unknown magic returns invalid")
    func unknownMagic() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x00, 0x00])
        let parser = MachOParser(data: data)
        let info = parser.parse()
        expect(info.isValid).to(beFalse())
    }

    @Test("Parsing minimal valid Mach-O 64 header returns valid info")
    func minimalMachO64() {
        let data = makeMinimalMachO64()
        let parser = MachOParser(data: data)
        let info = parser.parse()

        expect(info.isValid).to(beTrue())
        expect(info.architecture).to(equal("arm64"))
        expect(info.fileType).to(equal("Executable"))
        expect(info.isFatBinary).to(beFalse())
        expect(info.isEncrypted).to(beFalse())
        expect(info.symbols).to(beEmpty())
        expect(info.segments).to(beEmpty())
        expect(info.linkedLibraries).to(beEmpty())
    }

    @Test("Parsing x86_64 binary detects correct architecture")
    func x86Architecture() {
        let data = makeMinimalMachO64(cpuType: 0x01000007)
        let parser = MachOParser(data: data)
        let info = parser.parse()

        expect(info.isValid).to(beTrue())
        expect(info.architecture).to(equal("x86_64"))
    }

    @Test("Parsing dylib file type is detected")
    func dylibFileType() {
        let data = makeMinimalMachO64(fileType: 0x06)
        let parser = MachOParser(data: data)
        let info = parser.parse()

        expect(info.isValid).to(beTrue())
        expect(info.fileType).to(equal("Dynamic Library"))
    }

    @Test("Parsing truncated fat binary header returns invalid")
    func truncatedFatBinary() {
        var data = Data()
        var magic: UInt32 = 0xCAFEBABE
        data.append(Data(bytes: &magic, count: 4))
        // Only 4 bytes — not enough for nfat_arch
        let parser = MachOParser(data: data)
        let info = parser.parse()
        expect(info.isValid).to(beFalse())
    }

    @Test("Parsing fat binary with no known architecture returns invalid")
    func fatBinaryNoKnownArch() {
        var data = Data()
        var magic: UInt32 = 0xCAFEBABE
        data.append(Data(bytes: &magic, count: 4))
        var nfatArch: UInt32 = 1
        data.append(Data(bytes: &nfatArch, count: 4))
        // One arch entry with unknown CPU type
        var cpuType: UInt32 = 0x00000099
        data.append(Data(bytes: &cpuType, count: 4))
        var cpuSubtype: UInt32 = 0
        data.append(Data(bytes: &cpuSubtype, count: 4))
        var offset: UInt32 = 100
        data.append(Data(bytes: &offset, count: 4))
        var size: UInt32 = 32
        data.append(Data(bytes: &size, count: 4))
        var align: UInt32 = 14
        data.append(Data(bytes: &align, count: 4))

        let parser = MachOParser(data: data)
        let info = parser.parse()
        expect(info.isValid).to(beFalse())
    }

    @Test("DefaultMachOParserService delegates to MachOParser")
    func defaultParserService() {
        let service = DefaultMachOParserService()
        let data = makeMinimalMachO64()
        let info = service.parse(data: data)
        expect(info.isValid).to(beTrue())
        expect(info.architecture).to(equal("arm64"))
    }
}
