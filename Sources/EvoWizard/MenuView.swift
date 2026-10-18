import SwiftUI

struct MenuView: View {
    @Environment(Keyboard.self) private var keyboard
    @Environment(PresetStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var zone: LightZone = .keys

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if keyboard.isConnected {
                Picker("Zone", selection: $zone) {
                    ForEach(LightZone.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if keyboard.lighting[zone] != nil {
                    LightingEditor(zone: zone)
                } else {
                    Text("This zone did not respond.").foregroundStyle(.secondary)
                }
            } else {
                Label("Plug the EVO75 in with a USB cable.", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            Divider()
            PresetsSection()
            Divider()

            HStack {
                Button {
                    openWindow(id: "keymap")
                    NSApp.activate()
                } label: {
                    Label("Keymap & Shortcuts…", systemImage: "keyboard")
                }
                .disabled(!keyboard.isConnected)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(keyboard.isConnected ? .green : .secondary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(keyboard.productName).font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if keyboard.isBusy {
                ProgressView().controlSize(.small)
            } else if keyboard.isConnected {
                Button {
                    Task { await keyboard.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-read the keyboard state")
            }
        }
    }

    private var status: String {
        guard keyboard.isConnected else { return "Not connected" }
        let version = keyboard.protocolVersion.map { " · VIA v\($0)" } ?? ""
        return "Wired\(version) · \(keyboard.layerCount) layers"
    }
}

// MARK: - Lighting

struct LightingEditor: View {
    @Environment(Keyboard.self) private var keyboard
    let zone: LightZone

    private static let swatches: [(hue: UInt8, sat: UInt8)] = [
        (0, 255), (21, 255), (43, 255), (85, 255), (128, 255), (170, 255), (191, 255), (213, 255), (0, 0),
    ]

    var body: some View {
        let state = keyboard.lighting[zone]!
        VStack(alignment: .leading, spacing: 10) {
            row("Effect") {
                HStack(spacing: 4) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(Int(state.effect) <= zone.effects.lowerBound)
                    Picker("Effect", selection: binding(\.effect)) {
                        ForEach(Array(zone.effects), id: \.self) { effect in
                            Text(zone.effectName(effect)).tag(UInt8(effect))
                        }
                    }
                    .labelsHidden()
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Int(state.effect) >= zone.effects.upperBound)
                }
                .buttonStyle(.borderless)
            }
            row("Brightness") { Slider(value: slider(\.brightness), in: 0...255) }
            row("Speed") { Slider(value: slider(\.speed), in: 0...255) }
            row("Hue") { HueSlider(hue: slider(\.hue)) }
            row("Saturation") { Slider(value: slider(\.saturation), in: 0...255) }

            HStack(spacing: 6) {
                ForEach(Self.swatches.indices, id: \.self) { i in
                    let swatch = Self.swatches[i]
                    let selected = state.hue == swatch.hue && state.saturation == swatch.sat
                    Circle()
                        .fill(color(hue: swatch.hue, sat: swatch.sat))
                        .overlay(Circle().strokeBorder(.primary.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 1))
                        .frame(width: 22, height: 22)
                        .onTapGesture {
                            keyboard.update(zone) { $0.hue = swatch.hue; $0.saturation = swatch.sat }
                        }
                }
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(hue: state.hue, sat: state.saturation).opacity(0.25 + 0.75 * Double(state.brightness) / 255))
                    .frame(width: 34, height: 22)
                    .help("Current color")
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 74, alignment: .leading).foregroundStyle(.secondary)
            content()
        }
    }

    private func step(_ delta: Int) {
        keyboard.update(zone) { state in
            let next = Int(state.effect) + delta
            state.effect = UInt8(min(max(next, zone.effects.lowerBound), zone.effects.upperBound))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<LightingState, UInt8>) -> Binding<UInt8> {
        Binding(
            get: { keyboard.lighting[zone]?[keyPath: keyPath] ?? 0 },
            set: { value in keyboard.update(zone) { $0[keyPath: keyPath] = value } }
        )
    }

    private func slider(_ keyPath: WritableKeyPath<LightingState, UInt8>) -> Binding<Double> {
        Binding(
            get: { Double(keyboard.lighting[zone]?[keyPath: keyPath] ?? 0) },
            set: { value in keyboard.update(zone) { $0[keyPath: keyPath] = UInt8(value.rounded()) } }
        )
    }

    private func color(hue: UInt8, sat: UInt8) -> Color {
        Color(hue: Double(hue) / 255, saturation: Double(sat) / 255, brightness: 1)
    }
}

/// A 0…255 hue slider drawn over a rainbow track.
struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { geo in
            let x = hue / 255 * (geo.size.width - 14) + 7
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: stride(from: 0.0, through: 1.0, by: 1 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                Circle()
                    .fill(Color(hue: hue / 255, saturation: 1, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 1)
                    .frame(width: 14, height: 14)
                    .offset(x: x - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = (drag.location.x - 7) / (geo.size.width - 14)
                hue = (min(max(fraction, 0), 1) * 255).rounded()
            })
        }
        .frame(height: 18)
    }
}

// MARK: - Presets

struct PresetsSection: View {
    @Environment(Keyboard.self) private var keyboard
    @Environment(PresetStore.self) private var store
    @State private var newName = ""
    @State private var includeKeymap = false
    @State private var renaming: Preset.ID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets").font(.headline)
                Spacer()
                Menu {
                    Button("Import JSON…") { store.importWithPanel() }
                    Button("Export All…") { store.exportWithPanel(store.presets) }
                        .disabled(store.presets.isEmpty)
                    Divider()
                    Button("Reveal Presets File") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if store.presets.isEmpty {
                Text("No presets yet. Save the current setup below.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.presets) { preset in presetRow(preset) }
                    }
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                TextField("New preset name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Toggle("Keymap", isOn: $includeKeymap)
                    .toggleStyle(.checkbox)
                    .help("Also store the full keymap (all layers)")
                Button("Save", action: save)
                    .disabled(!keyboard.isConnected || newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let message = store.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(4))
                        store.message = nil
                    }
            }
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset) -> some View {
        HStack(spacing: 8) {
            if renaming == preset.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.rename(preset.id, to: renameText.trimmingCharacters(in: .whitespaces))
                        renaming = nil
                    }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.name).lineLimit(1)
                    Text(summary(preset)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Apply") { Task { await keyboard.apply(preset) } }
                .controlSize(.small)
                .disabled(!keyboard.isConnected)
            Menu {
                Button("Rename") { renameText = preset.name; renaming = preset.id }
                Button("Export…") { store.exportWithPanel([preset]) }
                Divider()
                Button("Delete", role: .destructive) { store.delete(preset.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func summary(_ preset: Preset) -> String {
        let zones = LightZone.allCases.compactMap { zone in
            preset.lighting[zone].map { "\(zone.title): \(zone.effectName(Int($0.effect)))" }
        }
        return (zones + (preset.keymap != nil ? ["keymap"] : [])).joined(separator: " · ")
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard keyboard.isConnected, !name.isEmpty else { return }
        store.add(keyboard.snapshot(name: name, includeKeymap: includeKeymap))
        newName = ""
    }
}
