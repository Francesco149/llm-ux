# lowpoly-painter

Specialized low-poly 3D modeler and handpainted texture painter with auto UVs and procedural bake effects

## Features
- **High-Performance Native UI**: Dear ImGui 1.92 with dynamic font rasterization.
- **Fluid Navigation**: Cursor-anchored zoom, smooth inertial pan, direct manipulation.
- **Non-Destructive Workflow**: Multi-session infinite undo (`Ctrl+Z` / `Ctrl+Y`), 300ms debounced autosave.
- **Single-Key Shortcuts**: Standard creator tool hotkeys with informative tooltip badges.
- **Cross-Platform**: Native Linux (SDL3) + Standalone Windows PE (D3D11 / MinGW cross).
- **Headless Automation**: Built-in `--shot`, `--test`, and `--lua` script execution for CI and visual verification.

## Building & Running

```sh
# Enter the hermetic dev environment
nix develop

# Build Windows standalone executable (default)
make -C editor

# Build native Linux executable
make -C editor linux

# Run headless tests
make -C editor test

# Capture headless UI screenshot
make -C editor shot
```

## License
MIT
