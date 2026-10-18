import Foundation

/// QMK keycodes (VIA protocol v12 / QMK ≥ 0.19 numbering).
enum Keycodes {
    struct Entry: Identifiable, Hashable {
        let code: UInt16
        let label: String
        var id: UInt16 { code }
    }

    struct Group: Identifiable {
        let name: String
        let entries: [Entry]
        var id: String { name }
    }

    static let none: UInt16 = 0x0000
    static let transparent: UInt16 = 0x0001

    /// Modifier bits used by QK_MODS (code = mods << 8 | basic) and mod-tap.
    struct Mods: OptionSet, Hashable {
        let rawValue: UInt16
        static let control = Mods(rawValue: 0x01)
        static let shift = Mods(rawValue: 0x02)
        static let option = Mods(rawValue: 0x04)
        static let command = Mods(rawValue: 0x08)
        static let right = Mods(rawValue: 0x10)

        var symbols: String {
            (contains(.right) ? "R" : "")
                + (contains(.control) ? "⌃" : "")
                + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "")
                + (contains(.command) ? "⌘" : "")
        }
    }

    static let groups: [Group] = {
        func e(_ code: UInt16, _ label: String) -> Entry { Entry(code: code, label: label) }
        let letters = (0..<26).map { e(0x04 + UInt16($0), String(UnicodeScalar(UInt8(65 + $0)))) }
        let digits = (0..<10).map { e(0x1E + UInt16($0), $0 == 9 ? "0" : "\($0 + 1)") }
        let fKeys = (0..<12).map { e(0x3A + UInt16($0), "F\($0 + 1)") } + (0..<12).map { e(0x68 + UInt16($0), "F\($0 + 13)") }
        return [
            Group(name: "Special", entries: [e(none, "None"), e(transparent, "▽ Trans")]),
            Group(name: "Letters", entries: letters),
            Group(name: "Numbers", entries: digits),
            Group(name: "Editing", entries: [
                e(0x28, "Enter"), e(0x29, "Esc"), e(0x2A, "Bksp"), e(0x2B, "Tab"), e(0x2C, "Space"),
                e(0x39, "Caps"), e(0x4C, "Del"), e(0x49, "Ins"), e(0x65, "Menu"),
            ]),
            Group(name: "Symbols", entries: [
                e(0x2D, "-"), e(0x2E, "="), e(0x2F, "["), e(0x30, "]"), e(0x31, "\\"), e(0x32, "#"),
                e(0x33, ";"), e(0x34, "'"), e(0x35, "`"), e(0x36, ","), e(0x37, "."), e(0x38, "/"), e(0x64, "§"),
            ]),
            Group(name: "Navigation", entries: [
                e(0x52, "↑"), e(0x51, "↓"), e(0x50, "←"), e(0x4F, "→"),
                e(0x4A, "Home"), e(0x4D, "End"), e(0x4B, "PgUp"), e(0x4E, "PgDn"),
                e(0x46, "PrtSc"), e(0x47, "ScrLk"), e(0x48, "Pause"),
            ]),
            Group(name: "Function", entries: fKeys),
            Group(name: "Modifiers", entries: [
                e(0xE0, "⌃ L"), e(0xE1, "⇧ L"), e(0xE2, "⌥ L"), e(0xE3, "⌘ L"),
                e(0xE4, "⌃ R"), e(0xE5, "⇧ R"), e(0xE6, "⌥ R"), e(0xE7, "⌘ R"),
            ]),
            Group(name: "Media", entries: [
                e(0xAE, "Play"), e(0xAB, "Next"), e(0xAC, "Prev"), e(0xAD, "Stop"),
                e(0xA8, "Mute"), e(0xA9, "Vol+"), e(0xAA, "Vol−"),
                e(0xBD, "Bri+"), e(0xBE, "Bri−"), e(0xC1, "Mission"), e(0xC2, "Launchpad"),
                e(0xB2, "Calc"), e(0xA6, "Sleep"),
            ]),
            Group(name: "Numpad", entries: (1...9).map { e(0x58 + UInt16($0), "KP\($0)") } + [
                e(0x62, "KP0"), e(0x63, "KP."), e(0x58, "KPEnt"), e(0x57, "KP+"),
                e(0x56, "KP−"), e(0x55, "KP*"), e(0x54, "KP/"), e(0x53, "NumLk"),
            ]),
        ]
    }()

    static func layerEntries(count: Int) -> [Entry] {
        (0..<count).flatMap { n in
            [Entry(code: 0x5220 | UInt16(n), label: "MO(\(n))"),
             Entry(code: 0x5260 | UInt16(n), label: "TG(\(n))"),
             Entry(code: 0x5200 | UInt16(n), label: "TO(\(n))")]
        }
    }

    private static let basicLabels: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for group in groups { for entry in group.entries { map[entry.code] = entry.label } }
        map[0x0000] = ""
        map[0x0001] = "▽"
        return map
    }()

    /// Short label for a keycode as shown on a keycap.
    static func label(_ code: UInt16) -> String {
        switch code {
        case 0x0000...0x00FF:
            return basicLabels[code] ?? hex(code)
        case 0x0100...0x1FFF:
            let mods = Mods(rawValue: (code >> 8) & 0x1F)
            return mods.symbols + (basicLabels[code & 0xFF] ?? hex(code & 0xFF))
        case 0x2000...0x3FFF:
            let mods = Mods(rawValue: (code >> 8) & 0x1F)
            return "MT(\(mods.symbols),\(basicLabels[code & 0xFF] ?? "?"))"
        case 0x4000...0x4FFF:
            return "LT\((code >> 8) & 0x0F)(\(basicLabels[code & 0xFF] ?? "?"))"
        case 0x5200...0x521F: return "TO(\(code & 0x1F))"
        case 0x5220...0x523F: return "MO(\(code & 0x1F))"
        case 0x5240...0x525F: return "DF(\(code & 0x1F))"
        case 0x5260...0x527F: return "TG(\(code & 0x1F))"
        case 0x5280...0x529F: return "OSL(\(code & 0x1F))"
        case 0x52C0...0x52DF: return "TT(\(code & 0x1F))"
        case 0x7E00...0x7E3F: return "KB\(code & 0x3F)"
        case 0x7E40...0x7E7F: return "USER\(code & 0x3F)"
        default: return hex(code)
        }
    }

    /// Splits a keycode into modifiers + basic key when it is a plain shortcut (QK_MODS) or basic key.
    static func decompose(_ code: UInt16) -> (mods: Mods, basic: UInt16)? {
        switch code {
        case 0x0000...0x00FF: (Mods(), code)
        case 0x0100...0x1FFF: (Mods(rawValue: (code >> 8) & 0x1F), code & 0xFF)
        default: nil
        }
    }

    static func compose(mods: Mods, basic: UInt16) -> UInt16 {
        mods.isEmpty || basic > 0xFF ? basic : (mods.rawValue << 8) | basic
    }

    static func hex(_ code: UInt16) -> String { String(format: "0x%04X", code) }
}
