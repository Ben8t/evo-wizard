import Foundation
import Observation

/// The two lighting zones exposed by the EVO75 firmware over VIA.
enum LightZone: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    case keys      // QMK RGB Matrix (per-key)
    case strip     // QMK RGBLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keys: "Keys"
        case .strip: "Strip"
        }
    }

    /// VIA custom-value channel id.
    var channel: UInt8 {
        switch self {
        case .keys: 3
        case .strip: 2
        }
    }

    /// Effect ids accepted by the firmware (probed on the device).
    var effects: ClosedRange<Int> {
        switch self {
        case .keys: 0...46
        case .strip: 1...10
        }
    }

    func effectName(_ effect: Int) -> String {
        if self == .keys && effect == 0 { return "Off" }
        if effect == 1 { return "Solid color" }
        return "Effect \(effect)"
    }
}

/// VIA lighting value ids within a channel.
private enum LightValue: UInt8 {
    case brightness = 1, effect = 2, speed = 3, color = 4
}

struct LightingState: Codable, Equatable {
    var brightness: UInt8
    var effect: UInt8
    var speed: UInt8
    var hue: UInt8
    var saturation: UInt8
}

@MainActor
@Observable
final class Keyboard {
    static let vendorID = 0x36B0
    static let productID = 0x30A9
    static let rows = 6
    static let cols = 16

    private(set) var isConnected = false
    private(set) var productName = "EVO75"
    private(set) var protocolVersion: Int?
    private(set) var layerCount = 4
    private(set) var isBusy = false
    private(set) var lighting: [LightZone: LightingState] = [:]
    /// `keymap[layer][row * cols + col]`
    private(set) var keymap: [[UInt16]] = []

    @ObservationIgnored private let transport = VIATransport(vendorID: vendorID, productID: productID)
    @ObservationIgnored private var written: [LightZone: LightingState] = [:]
    @ObservationIgnored private var pushing: Set<LightZone> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        transport.onConnectionChange = { [weak self] connected, name in
            Task { @MainActor in await self?.connectionChanged(connected, name: name) }
        }
        transport.start()
    }

    private func connectionChanged(_ connected: Bool, name: String?) async {
        isConnected = connected
        if let name { productName = name }
        if connected {
            await refresh()
        } else {
            lighting = [:]
            written = [:]
            keymap = []
        }
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        if let r = await transport.request([VIACommand.protocolVersion.rawValue]), r[0] == 0x01 {
            protocolVersion = Int(r[1]) << 8 | Int(r[2])
        }
        if let r = await transport.request([VIACommand.layerCount.rawValue]), r[0] == 0x11 {
            layerCount = Int(r[1])
        }
        for zone in LightZone.allCases {
            let state = await readLighting(zone)
            lighting[zone] = state
            written[zone] = state
        }
        keymap = await readKeymap()
    }

    // MARK: - Lighting

    /// Edits a zone locally and streams the change to the keyboard (latest value wins).
    func update(_ zone: LightZone, _ change: (inout LightingState) -> Void) {
        guard var state = lighting[zone] else { return }
        change(&state)
        lighting[zone] = state
        push(zone)
    }

    private func push(_ zone: LightZone) {
        guard !pushing.contains(zone) else { return }
        pushing.insert(zone)
        Task {
            while let target = lighting[zone], target != written[zone] {
                await writeLighting(zone, target, previous: written[zone])
                written[zone] = target
            }
            pushing.remove(zone)
            scheduleSave()
        }
    }

    private func readLighting(_ zone: LightZone) async -> LightingState? {
        func get(_ value: LightValue) async -> [UInt8]? {
            let r = await transport.request([VIACommand.customGetValue.rawValue, zone.channel, value.rawValue])
            return r?[0] == VIACommand.customGetValue.rawValue ? r : nil
        }
        guard let b = await get(.brightness), let e = await get(.effect),
              let s = await get(.speed), let c = await get(.color) else { return nil }
        return LightingState(brightness: b[3], effect: e[3], speed: s[3], hue: c[3], saturation: c[4])
    }

    private func writeLighting(_ zone: LightZone, _ state: LightingState, previous: LightingState?) async {
        func set(_ value: LightValue, _ data: UInt8...) async {
            _ = await transport.request([VIACommand.customSetValue.rawValue, zone.channel, value.rawValue] + data)
        }
        if state.effect != previous?.effect { await set(.effect, state.effect) }
        if state.brightness != previous?.brightness { await set(.brightness, state.brightness) }
        if state.speed != previous?.speed { await set(.speed, state.speed) }
        if state.hue != previous?.hue || state.saturation != previous?.saturation {
            await set(.color, state.hue, state.saturation)
        }
    }

    /// Persists lighting to the keyboard's EEPROM shortly after the last edit.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await saveLighting()
        }
    }

    func saveLighting() async {
        for zone in LightZone.allCases {
            _ = await transport.request([VIACommand.customSave.rawValue, zone.channel])
        }
    }

    // MARK: - Keymap

    private func readKeymap() async -> [[UInt16]] {
        let keysPerLayer = Self.rows * Self.cols
        let total = layerCount * keysPerLayer * 2
        var bytes: [UInt8] = []
        var offset = 0
        while offset < total {
            let size = min(28, total - offset)
            guard let r = await transport.request([
                VIACommand.keymapGetBuffer.rawValue, UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(size),
            ]), r[0] == VIACommand.keymapGetBuffer.rawValue else { return [] }
            bytes += r[4..<(4 + size)]
            offset += size
        }
        let codes = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        return stride(from: 0, to: codes.count, by: keysPerLayer).map { Array(codes[$0..<($0 + keysPerLayer)]) }
    }

    func keycode(layer: Int, row: Int, col: Int) -> UInt16? {
        guard keymap.indices.contains(layer) else { return nil }
        return keymap[layer][row * Self.cols + col]
    }

    @discardableResult
    func setKeycode(_ code: UInt16, layer: Int, row: Int, col: Int) async -> Bool {
        let r = await transport.request([
            VIACommand.setKeycode.rawValue, UInt8(layer), UInt8(row), UInt8(col), UInt8(code >> 8), UInt8(code & 0xFF),
        ])
        guard r?[0] == VIACommand.setKeycode.rawValue else { return false }
        keymap[layer][row * Self.cols + col] = code
        return true
    }

    // MARK: - Presets

    func snapshot(name: String, includeKeymap: Bool) -> Preset {
        Preset(name: name, lighting: lighting, keymap: includeKeymap && !keymap.isEmpty ? keymap : nil)
    }

    func apply(_ preset: Preset) async {
        isBusy = true
        defer { isBusy = false }
        for (zone, state) in preset.lighting where lighting[zone] != nil {
            lighting[zone] = state
            push(zone)
        }
        if let target = preset.keymap {
            for layer in 0..<min(target.count, keymap.count) {
                for index in 0..<min(target[layer].count, keymap[layer].count) where target[layer][index] != keymap[layer][index] {
                    await setKeycode(target[layer][index], layer: layer, row: index / Self.cols, col: index % Self.cols)
                }
            }
        }
    }
}
