# Evo Wizard

macOS menu-bar manager for the **EVO75** (RDMCTMZT, VID `0x36B0` / PID `0x30A9`) over its VIA raw-HID interface, wired.

- **Lighting**: two zones, Keys (RGB Matrix, effects 0–46) and Strip (RGBLight, effects 1–10). Effect, brightness, speed, hue and saturation are applied live and saved to EEPROM 1.5 s after the last change.
- **Keymap & shortcuts**: remap any matrix position on any of the 4 layers to a key, a modifier combo (e.g. `⌘⇧4`), a layer key (`MO`/`TG`/`TO`) or a raw keycode.
- **Presets**: lighting, plus optionally the full keymap, stored in `~/Library/Application Support/EvoWizard/presets.json`. Import and export as JSON.

```sh
swift run                 # dev
./scripts/bundle.sh       # -> build/EvoWizard.app
```

## Preset JSON

```json
{
  "format": "evo-wizard.presets",
  "version": 1,
  "presets": [
    {
      "name": "Ocean",
      "lighting": {
        "keys":  { "brightness": 200, "effect": 1, "speed": 127, "hue": 140, "saturation": 255 },
        "strip": { "brightness": 120, "effect": 1, "speed": 0,   "hue": 170, "saturation": 255 }
      }
    }
  ]
}
```

`keymap`, when present, is one array of 96 keycodes (row × 16 + col) per layer. `id`, `createdAt` and `keymap` are optional on import. Import also accepts a bare array of presets or a single preset object.

Effect names are numbered because the vendor firmware's effect list doesn't match QMK's default ordering.
