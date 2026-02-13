import Foundation

// MARK: - Mach-O Constants

private let MH_MAGIC_64: UInt32    = 0xFEEDFACF
private let MH_CIGAM_64: UInt32    = 0xCFFAEDFE
private let FAT_MAGIC: UInt32      = 0xCAFEBABE
private let FAT_CIGAM: UInt32      = 0xBEBAFECA
private let FAT_MAGIC_64: UInt32   = 0xCAFEBABF

private let MH_EXECUTE: UInt32     = 0x02
private let MH_DYLIB: UInt32       = 0x06

private let LC_SEGMENT_64: UInt32          = 0x19
private let LC_SYMTAB: UInt32              = 0x02
private let LC_DYSYMTAB: UInt32            = 0x0B
private let LC_LOAD_DYLIB: UInt32          = 0x0C
private let LC_LOAD_WEAK_DYLIB: UInt32     = 0x80000018
private let LC_RPATH: UInt32               = 0x8000001C
private let LC_ENCRYPTION_INFO_64: UInt32  = 0x2C

private let CPU_TYPE_ARM64: UInt32  = 0x0100000C
private let CPU_TYPE_X86_64: UInt32 = 0x01000007

private let N_EXT: UInt8  = 0x01
private let N_UNDF: UInt8 = 0x00
private let N_STAB: UInt8 = 0xE0
private let N_TYPE: UInt8 = 0x0E
private let N_SECT: UInt8 = 0x0E

// MARK: - Parsed Types

/// Information extracted from a Mach-O binary.
struct MachOInfo {
    let isValid: Bool
    let isFatBinary: Bool
    let isEncrypted: Bool
    let architecture: String
    let fileType: String
    let segments: [SegmentInfo]
    let symbols: [SymbolInfo]
    let linkedLibraries: [String]
    let extractedStrings: [String]
    let objcClasses: [String]
    let objcSelectors: [String]
    let objcProtocols: [String]
    let swiftTypeDescriptors: [String]
    let swiftProtocolConformances: [String]
    let sections: [SectionInfo]
    let totalTextSize: UInt64
    let totalDataSize: UInt64

    static let invalid = MachOInfo(
        isValid: false, isFatBinary: false, isEncrypted: false,
        architecture: "Unknown", fileType: "Unknown",
        segments: [], symbols: [], linkedLibraries: [],
        extractedStrings: [], objcClasses: [], objcSelectors: [],
        objcProtocols: [], swiftTypeDescriptors: [],
        swiftProtocolConformances: [], sections: [],
        totalTextSize: 0, totalDataSize: 0
    )
}

struct SegmentInfo {
    let name: String
    let vmAddress: UInt64
    let vmSize: UInt64
    let fileOffset: UInt64
    let fileSize: UInt64
    let sections: [SectionInfo]
}

struct SectionInfo {
    let name: String
    let segmentName: String
    let address: UInt64
    let size: UInt64
    let offset: UInt32
    let align: UInt32
}

struct SymbolInfo {
    let name: String
    let type: UInt8
    let sectionIndex: UInt8
    let flags: UInt16
    let value: UInt64
    let isExternal: Bool
    let isUndefined: Bool
    let isDefined: Bool
    let isDebug: Bool
}

// MARK: - MachOParser

/// Parses Mach-O binary format used by iOS/macOS applications.
/// Extracts symbols, segments, sections, and metadata needed for static analysis.
final class MachOParser {

    private let data: Data
    private var offset: Int = 0
    private var shouldSwapBytes: Bool = false

    init(data: Data) {
        self.data = data
    }

    /// Parse the Mach-O binary and return extracted information.
    func parse() -> MachOInfo {
        guard data.count >= 4 else { return .invalid }

        let magic = readUInt32(at: 0)

        // Check for fat/universal binary
        if magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 {
            return parseFatBinary(magic: magic)
        }

        // Check for 64-bit Mach-O
        if magic == MH_MAGIC_64 || magic == MH_CIGAM_64 {
            shouldSwapBytes = (magic == MH_CIGAM_64)
            return parseMachO64(at: 0, isFat: false)
        }

        return .invalid
    }

    // MARK: - Fat Binary Parsing

    private func parseFatBinary(magic: UInt32) -> MachOInfo {
        let needsSwap = (magic == FAT_CIGAM)

        guard data.count >= 8 else { return .invalid }

        let nfatArch = readUInt32(at: 4, swap: needsSwap)

        // Look for arm64 slice first, then x86_64
        var arm64Offset: UInt64 = 0
        var x86Offset: UInt64 = 0
        var foundArm64 = false
        var foundX86 = false

        var archOffset = 8
        for _ in 0..<nfatArch {
            guard archOffset + 20 <= data.count else { break }

            let cpuType = readUInt32(at: archOffset, swap: needsSwap)
            let sliceOffset = readUInt32(at: archOffset + 8, swap: needsSwap)

            if cpuType == CPU_TYPE_ARM64 {
                arm64Offset = UInt64(sliceOffset)
                foundArm64 = true
            } else if cpuType == CPU_TYPE_X86_64 {
                x86Offset = UInt64(sliceOffset)
                foundX86 = true
            }

            archOffset += 20
        }

        let targetOffset: Int
        if foundArm64 {
            targetOffset = Int(arm64Offset)
        } else if foundX86 {
            targetOffset = Int(x86Offset)
        } else {
            return .invalid
        }

        guard targetOffset < data.count else { return .invalid }

        let sliceMagic = readUInt32(at: targetOffset)
        if sliceMagic == MH_MAGIC_64 || sliceMagic == MH_CIGAM_64 {
            shouldSwapBytes = (sliceMagic == MH_CIGAM_64)
            var result = parseMachO64(at: targetOffset, isFat: true)
            return result
        }

        return .invalid
    }

    // MARK: - Mach-O 64-bit Parsing

    private func parseMachO64(at baseOffset: Int, isFat: Bool) -> MachOInfo {
        guard baseOffset + 32 <= data.count else { return .invalid }

        // Parse header
        let cpuType = readUInt32(at: baseOffset + 4)
        let fileType = readUInt32(at: baseOffset + 12)
        let ncmds = readUInt32(at: baseOffset + 16)
        let sizeOfCmds = readUInt32(at: baseOffset + 20)

        let architecture: String
        switch cpuType {
        case CPU_TYPE_ARM64: architecture = "arm64"
        case CPU_TYPE_X86_64: architecture = "x86_64"
        default: architecture = "unknown (\(cpuType))"
        }

        let fileTypeStr: String
        switch fileType {
        case MH_EXECUTE: fileTypeStr = "Executable"
        case MH_DYLIB: fileTypeStr = "Dynamic Library"
        default: fileTypeStr = "Other (\(fileType))"
        }

        // Parse load commands
        var segments: [SegmentInfo] = []
        var linkedLibraries: [String] = []
        var symtabOffset: UInt32 = 0
        var symtabCount: UInt32 = 0
        var strtabOffset: UInt32 = 0
        var strtabSize: UInt32 = 0
        var isEncrypted = false

        var cmdOffset = baseOffset + 32 // sizeof(mach_header_64)
        for _ in 0..<ncmds {
            guard cmdOffset + 8 <= data.count else { break }

            let cmd = readUInt32(at: cmdOffset)
            let cmdSize = readUInt32(at: cmdOffset + 4)

            switch cmd {
            case LC_SEGMENT_64:
                if let segment = parseSegment64(at: cmdOffset, base: baseOffset) {
                    segments.append(segment)
                }

            case LC_SYMTAB:
                guard cmdOffset + 24 <= data.count else { break }
                symtabOffset = readUInt32(at: cmdOffset + 8)
                symtabCount = readUInt32(at: cmdOffset + 12)
                strtabOffset = readUInt32(at: cmdOffset + 16)
                strtabSize = readUInt32(at: cmdOffset + 20)

            case LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB:
                if let lib = parseDylib(at: cmdOffset, cmdSize: cmdSize) {
                    linkedLibraries.append(lib)
                }

            case LC_ENCRYPTION_INFO_64:
                guard cmdOffset + 24 <= data.count else { break }
                let cryptId = readUInt32(at: cmdOffset + 16)
                isEncrypted = cryptId != 0

            default:
                break
            }

            cmdOffset += Int(cmdSize)
        }

        // Parse symbol table
        let symbols = parseSymbolTable(
            symtabOffset: Int(symtabOffset),
            symtabCount: Int(symtabCount),
            strtabOffset: Int(strtabOffset),
            strtabSize: Int(strtabSize)
        )

        // Extract strings from relevant sections
        let allSections = segments.flatMap { $0.sections }
        let extractedStrings = extractStrings(from: allSections)
        let objcClasses = extractObjCClasses(from: allSections, symbols: symbols)
        let objcSelectors = extractObjCSelectors(from: allSections)
        let objcProtocols = extractObjCProtocols(from: symbols)
        let swiftTypes = extractSwiftTypes(from: allSections, symbols: symbols)
        let swiftConformances = extractSwiftConformances(from: symbols)

        let totalTextSize = segments
            .filter { $0.name == "__TEXT" }
            .reduce(0) { $0 + $1.vmSize }
        let totalDataSize = segments
            .filter { $0.name == "__DATA" || $0.name == "__DATA_CONST" }
            .reduce(0) { $0 + $1.vmSize }

        return MachOInfo(
            isValid: true,
            isFatBinary: isFat,
            isEncrypted: isEncrypted,
            architecture: architecture,
            fileType: fileTypeStr,
            segments: segments,
            symbols: symbols,
            linkedLibraries: linkedLibraries,
            extractedStrings: extractedStrings,
            objcClasses: objcClasses,
            objcSelectors: objcSelectors,
            objcProtocols: objcProtocols,
            swiftTypeDescriptors: swiftTypes,
            swiftProtocolConformances: swiftConformances,
            sections: allSections,
            totalTextSize: totalTextSize,
            totalDataSize: totalDataSize
        )
    }

    // MARK: - Segment Parsing

    private func parseSegment64(at offset: Int, base: Int) -> SegmentInfo? {
        // segment_command_64 is 72 bytes
        guard offset + 72 <= data.count else { return nil }

        let segName = readString(at: offset + 8, maxLength: 16)
        let vmAddr = readUInt64(at: offset + 24)
        let vmSize = readUInt64(at: offset + 32)
        let fileOffset = readUInt64(at: offset + 40)
        let fileSize = readUInt64(at: offset + 48)
        let nsects = readUInt32(at: offset + 64)

        var sections: [SectionInfo] = []
        var sectOffset = offset + 72 // after segment_command_64

        for _ in 0..<nsects {
            guard sectOffset + 80 <= data.count else { break }

            let sectName = readString(at: sectOffset, maxLength: 16)
            let sectSegName = readString(at: sectOffset + 16, maxLength: 16)
            let addr = readUInt64(at: sectOffset + 32)
            let size = readUInt64(at: sectOffset + 40)
            let sectFileOffset = readUInt32(at: sectOffset + 48)
            let align = readUInt32(at: sectOffset + 52)

            sections.append(SectionInfo(
                name: sectName,
                segmentName: sectSegName,
                address: addr,
                size: size,
                offset: sectFileOffset,
                align: align
            ))

            sectOffset += 80 // sizeof(section_64)
        }

        return SegmentInfo(
            name: segName,
            vmAddress: vmAddr,
            vmSize: vmSize,
            fileOffset: fileOffset,
            fileSize: fileSize,
            sections: sections
        )
    }

    // MARK: - Dylib Parsing

    private func parseDylib(at offset: Int, cmdSize: UInt32) -> String? {
        guard offset + 12 <= data.count else { return nil }

        let nameOffset = readUInt32(at: offset + 8)
        let stringStart = offset + Int(nameOffset)
        let stringEnd = offset + Int(cmdSize)

        guard stringStart < stringEnd, stringStart < data.count else { return nil }

        return readCString(at: stringStart, maxLength: stringEnd - stringStart)
    }

    // MARK: - Symbol Table Parsing

    private func parseSymbolTable(
        symtabOffset: Int,
        symtabCount: Int,
        strtabOffset: Int,
        strtabSize: Int
    ) -> [SymbolInfo] {
        guard symtabOffset > 0, symtabCount > 0 else { return [] }
        guard strtabOffset > 0, strtabSize > 0 else { return [] }
        guard symtabOffset + symtabCount * 16 <= data.count else { return [] }
        guard strtabOffset + strtabSize <= data.count else { return [] }

        var symbols: [SymbolInfo] = []
        symbols.reserveCapacity(min(symtabCount, 100_000)) // Cap for safety

        let maxSymbols = min(symtabCount, 100_000) // Safety limit

        for i in 0..<maxSymbols {
            let entryOffset = symtabOffset + i * 16 // nlist_64 is 16 bytes
            guard entryOffset + 16 <= data.count else { break }

            let strIndex = readUInt32(at: entryOffset)
            let nType = readUInt8(at: entryOffset + 4)
            let nSect = readUInt8(at: entryOffset + 5)
            let nDesc = readUInt16(at: entryOffset + 6)
            let nValue = readUInt64(at: entryOffset + 8)

            // Skip debug symbols for performance
            let isDebug = (nType & N_STAB) != 0
            if isDebug { continue }

            let isExternal = (nType & N_EXT) != 0
            let typeField = nType & N_TYPE
            let isUndefined = typeField == N_UNDF
            let isDefined = typeField == N_SECT

            // Read symbol name from string table
            let nameStart = strtabOffset + Int(strIndex)
            guard nameStart < strtabOffset + strtabSize else { continue }

            let name = readCString(
                at: nameStart,
                maxLength: min(4096, strtabOffset + strtabSize - nameStart)
            ) ?? ""

            guard !name.isEmpty else { continue }

            symbols.append(SymbolInfo(
                name: name,
                type: nType,
                sectionIndex: nSect,
                flags: nDesc,
                value: nValue,
                isExternal: isExternal,
                isUndefined: isUndefined,
                isDefined: isDefined,
                isDebug: isDebug
            ))
        }

        return symbols
    }

    // MARK: - String and Metadata Extraction

    private func extractStrings(from sections: [SectionInfo]) -> [String] {
        var strings: [String] = []

        let stringSections = sections.filter {
            $0.name == "__cstring" || $0.name == "__objc_methname" ||
            $0.name == "__objc_classname" || $0.name == "__swift5_reflstr" ||
            $0.name == "__ustring"
        }

        for section in stringSections {
            let start = Int(section.offset)
            let size = Int(section.size)
            guard start + size <= data.count, size > 0 else { continue }

            let sectionData = data[start..<(start + size)]
            var current = ""

            for byte in sectionData {
                if byte == 0 {
                    if !current.isEmpty {
                        strings.append(current)
                        current = ""
                    }
                } else if let scalar = Unicode.Scalar(byte), scalar.isASCII {
                    current.append(Character(scalar))
                }
            }

            if !current.isEmpty {
                strings.append(current)
            }
        }

        return strings
    }

    private func extractObjCClasses(from sections: [SectionInfo], symbols: [SymbolInfo]) -> [String] {
        var classes: [String] = []

        // Extract from class name section
        if let section = sections.first(where: { $0.name == "__objc_classname" }) {
            let start = Int(section.offset)
            let size = Int(section.size)
            if start + size <= data.count {
                let sectionData = data[start..<(start + size)]
                var current = ""
                for byte in sectionData {
                    if byte == 0 {
                        if !current.isEmpty {
                            classes.append(current)
                            current = ""
                        }
                    } else if let scalar = Unicode.Scalar(byte), scalar.isASCII {
                        current.append(Character(scalar))
                    }
                }
                if !current.isEmpty {
                    classes.append(current)
                }
            }
        }

        // Also extract from symbols
        let classSymbols = symbols.filter { $0.name.hasPrefix("_OBJC_CLASS_$_") }
        for symbol in classSymbols {
            let className = String(symbol.name.dropFirst("_OBJC_CLASS_$_".count))
            if !className.isEmpty && !classes.contains(className) {
                classes.append(className)
            }
        }

        return classes
    }

    private func extractObjCSelectors(from sections: [SectionInfo]) -> [String] {
        guard let section = sections.first(where: { $0.name == "__objc_methname" || $0.name == "__objc_selrefs" }) else {
            return []
        }

        var selectors: [String] = []
        let start = Int(section.offset)
        let size = Int(section.size)
        guard start + size <= data.count else { return [] }

        let sectionData = data[start..<(start + size)]
        var current = ""
        for byte in sectionData {
            if byte == 0 {
                if !current.isEmpty {
                    selectors.append(current)
                    current = ""
                }
            } else if let scalar = Unicode.Scalar(byte), scalar.isASCII {
                current.append(Character(scalar))
            }
        }

        return selectors
    }

    private func extractObjCProtocols(from symbols: [SymbolInfo]) -> [String] {
        symbols
            .filter { $0.name.hasPrefix("_OBJC_PROTOCOL_$_") }
            .map { String($0.name.dropFirst("_OBJC_PROTOCOL_$_".count)) }
    }

    private func extractSwiftTypes(from sections: [SectionInfo], symbols: [SymbolInfo]) -> [String] {
        var types: [String] = []

        // Extract from swift5_types section (type descriptors)
        // These are relative pointers, so we extract what we can from symbols
        let swiftSymbols = symbols.filter {
            $0.name.contains("$s") || $0.name.contains("_$s") ||
            $0.name.hasPrefix("$S") || $0.name.hasPrefix("_$S")
        }

        // Demangle common patterns
        for symbol in swiftSymbols {
            if let typeName = demangleSwiftSymbol(symbol.name) {
                if !types.contains(typeName) {
                    types.append(typeName)
                }
            }
        }

        return types
    }

    private func extractSwiftConformances(from symbols: [SymbolInfo]) -> [String] {
        symbols
            .filter { $0.name.contains("Mc") || $0.name.contains("MC") || $0.name.contains("Ma") }
            .compactMap { demangleSwiftSymbol($0.name) }
    }

    /// Basic Swift symbol demangling for common patterns.
    private func demangleSwiftSymbol(_ mangled: String) -> String? {
        var name = mangled
        if name.hasPrefix("_") { name = String(name.dropFirst()) }

        // Look for type metadata accessors
        if name.contains("CMa") || name.contains("CMn") || name.contains("CN") {
            // This is type metadata - extract module and type name if possible
            return extractSwiftName(from: name)
        }

        // Look for protocol conformance descriptors
        if name.contains("Mc") || name.contains("MC") {
            return extractSwiftName(from: name)
        }

        // General swift symbol
        if name.hasPrefix("$s") || name.hasPrefix("$S") {
            return extractSwiftName(from: name)
        }

        return nil
    }

    private func extractSwiftName(from symbol: String) -> String? {
        // Very basic extraction - look for module name + type name pattern
        // Full demangling would require swift-demangle, but we can extract useful info
        var remaining = symbol
        if remaining.hasPrefix("$s") || remaining.hasPrefix("$S") {
            remaining = String(remaining.dropFirst(2))
        }

        // Try to extract numeric-prefixed components (length + name)
        var components: [String] = []
        var idx = remaining.startIndex

        while idx < remaining.endIndex {
            // Try to read a number
            var numStr = ""
            while idx < remaining.endIndex, remaining[idx].isNumber {
                numStr.append(remaining[idx])
                idx = remaining.index(after: idx)
            }

            if let len = Int(numStr), len > 0 {
                let endIdx = remaining.index(idx, offsetBy: len, limitedBy: remaining.endIndex) ?? remaining.endIndex
                let component = String(remaining[idx..<endIdx])
                components.append(component)
                idx = endIdx
            } else {
                // Skip non-numeric, non-alpha characters
                idx = remaining.index(after: idx)
            }
        }

        if components.count >= 2 {
            return "\(components[0]).\(components[1])"
        } else if components.count == 1 {
            return components[0]
        }

        return nil
    }

    // MARK: - Binary Reading Helpers

    private func readUInt8(at offset: Int) -> UInt8 {
        guard offset < data.count else { return 0 }
        return data[offset]
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 2))
        }
        return shouldSwapBytes ? value.byteSwapped : value
    }

    private func readUInt32(at offset: Int, swap: Bool? = nil) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        let doSwap = swap ?? shouldSwapBytes
        return doSwap ? value.byteSwapped : value
    }

    private func readUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 8))
        }
        return shouldSwapBytes ? value.byteSwapped : value
    }

    private func readString(at offset: Int, maxLength: Int) -> String {
        guard offset + maxLength <= data.count else { return "" }
        let subdata = data[offset..<(offset + maxLength)]
        var bytes: [UInt8] = []
        for byte in subdata {
            if byte == 0 { break }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private func readCString(at offset: Int, maxLength: Int) -> String? {
        guard offset < data.count else { return nil }
        let end = min(offset + maxLength, data.count)
        var bytes: [UInt8] = []
        for i in offset..<end {
            let byte = data[i]
            if byte == 0 { break }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
