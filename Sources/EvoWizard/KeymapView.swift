import SwiftUI

struct KeyPosition: Hashable {
    let row: Int
    let col: Int
}

/// Matrix-grid keymap editor. Each cell is a (row, col) position in the 6×16 switch matrix.
struct KeymapView: View {
    @Environment(Keyboard.self) private var keyboard
    @State private var layer = 0
    @State private var selected: KeyPosition?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Layer", selection: $layer) {
                    ForEach(0..<keyboard.layerCount, id: \.self) { Text("Layer \($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Spacer()
                Text("Click a key to remap it or bind a shortcut. Changes are written to the keyboard immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if keyboard.keymap.isEmpty {
                ContentUnavailableView("No keymap", systemImage: "keyboard",
                                       description: Text("Connect the EVO75 to read its keymap."))
                    .frame(height: 280)
            } else {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<Keyboard.rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<Keyboard.cols, id: \.self) { col in
                                keyCell(KeyPosition(row: row, col: col))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 16 * 48 + 32)
    }

    private func keyCell(_ position: KeyPosition) -> some View {
        let code = keyboard.keycode(layer: layer, row: position.row, col: position.col) ?? 0
        let isSelected = selected == position
        return Button {
            selected = position
        } label: {
            Text(Keycodes.label(code))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(code == Keycodes.none ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.quaternary))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
                .foregroundStyle(code == Keycodes.none ? .tertiary : .primary)
        }
        .buttonStyle(.plain)
        .help("Row \(position.row), col \(position.col) · \(Keycodes.hex(code))")
        .popover(isPresented: Binding(
            get: { selected == position },
            set: { if !$0 { selected = nil } }
        )) {
            KeyEditor(layer: layer, position: position, current: code) { selected = nil }
                .environment(keyboard)
        }
    }
}

/// Picks a keycode: a plain key, a shortcut (modifiers + key), a layer key or a raw hex value.
struct KeyEditor: View {
    @Environment(Keyboard.self) private var keyboard
    let layer: Int
    let position: KeyPosition
    let current: UInt16
    let dismiss: () -> Void

    @State private var mods: Keycodes.Mods = []
    @State private var search = ""
    @State private var rawHex = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layer \(layer) · R\(position.row) C\(position.col)").font(.headline)
                Spacer()
                Text("\(Keycodes.label(current))  \(Keycodes.hex(current))")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("Shortcut mods").font(.caption).foregroundStyle(.secondary)
                modToggle("⌃", .control)
                modToggle("⌥", .option)
                modToggle("⇧", .shift)
                modToggle("⌘", .command)
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 120)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredGroups) { group in
                        Text(group.name).font(.caption.bold()).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 4), count: 8), spacing: 4) {
                            ForEach(group.entries) { entry in
                                Button(entry.label) { assign(entryCode(entry, group: group)) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .frame(width: 58)
                            }
                        }
                    }
                }
            }
            .frame(height: 280)

            HStack {
                TextField("Raw keycode, e.g. 0x7E0F", text: $rawHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(assignRaw)
                Button("Set", action: assignRaw)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding(14)
        .frame(width: 520)
        .onAppear {
            if let (m, _) = Keycodes.decompose(current) { mods = m }
        }
    }

    private var filteredGroups: [Keycodes.Group] {
        let all = Keycodes.groups + [Keycodes.Group(name: "Layers", entries: Keycodes.layerEntries(count: keyboard.layerCount))]
        guard !search.isEmpty else { return all }
        return all.compactMap { group in
            let entries = group.entries.filter { $0.label.localizedCaseInsensitiveContains(search) }
            return entries.isEmpty ? nil : Keycodes.Group(name: group.name, entries: entries)
        }
    }

    /// Modifiers only apply to basic keys (not layer / special keys).
    private func entryCode(_ entry: Keycodes.Entry, group: Keycodes.Group) -> UInt16 {
        guard group.name != "Special", group.name != "Layers" else { return entry.code }
        return Keycodes.compose(mods: mods, basic: entry.code)
    }

    private func modToggle(_ symbol: String, _ mod: Keycodes.Mods) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { mods.contains(mod) },
            set: { if $0 { mods.insert(mod) } else { mods.remove(mod) } }
        ))
        .toggleStyle(.button)
        .controlSize(.small)
    }

    private func assignRaw() {
        let text = rawHex.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = text.hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard let code = UInt16(digits, radix: 16) else { error = "Invalid hex"; return }
        assign(code)
    }

    private func assign(_ code: UInt16) {
        Task {
            if await keyboard.setKeycode(code, layer: layer, row: position.row, col: position.col) {
                dismiss()
            } else {
                error = "Keyboard did not accept it"
            }
        }
    }
}
