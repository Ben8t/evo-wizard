import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var lighting: [LightZone: LightingState]
    /// Optional full keymap, `keymap[layer][row * 16 + col]`.
    var keymap: [[UInt16]]?

    init(name: String, lighting: [LightZone: LightingState], keymap: [[UInt16]]? = nil) {
        self.name = name
        self.lighting = lighting
        self.keymap = keymap
    }

    // Lenient decoding so hand-written JSON can omit id / createdAt / keymap.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lighting = try c.decodeIfPresent([LightZone: LightingState].self, forKey: .lighting) ?? [:]
        keymap = try c.decodeIfPresent([[UInt16]].self, forKey: .keymap)
    }
}

/// On-disk / export format.
struct PresetFile: Codable {
    var format = "evo-wizard.presets"
    var version = 1
    var presets: [Preset]
}

@MainActor
@Observable
final class PresetStore {
    private(set) var presets: [Preset] = []
    var message: String?

    @ObservationIgnored let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EvoWizard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL), let decoded = try? Self.decode(data) {
            presets = decoded
        }
    }

    func add(_ preset: Preset) {
        presets.append(preset)
        persist()
    }

    func rename(_ id: Preset.ID, to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        presets[i].name = name
        persist()
    }

    func delete(_ id: Preset.ID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            try Self.encode(presets).write(to: fileURL, options: .atomic)
        } catch {
            message = "Could not save presets: \(error.localizedDescription)"
        }
    }

    // MARK: - Import / export

    func exportWithPanel(_ selection: [Preset]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = selection.count == 1 ? "\(selection[0].name).json" : "evo75-presets.json"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.encode(selection).write(to: url, options: .atomic)
            message = "Exported \(selection.count) preset\(selection.count == 1 ? "" : "s")."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var count = 0
        for url in panel.urls {
            do {
                let imported = try Self.decode(Data(contentsOf: url))
                for var preset in imported {
                    preset.id = UUID()
                    presets.append(preset)
                    count += 1
                }
            } catch {
                message = "\(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }
        persist()
        message = "Imported \(count) preset\(count == 1 ? "" : "s")."
    }

    // MARK: - Coding

    private static func encode(_ presets: [Preset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(PresetFile(presets: presets))
    }

    /// Accepts a `PresetFile`, a bare array of presets, or a single preset.
    private static func decode(_ data: Data) throws -> [Preset] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(PresetFile.self, from: data) { return file.presets }
        if let list = try? decoder.decode([Preset].self, from: data) { return list }
        return [try decoder.decode(Preset.self, from: data)]
    }
}
