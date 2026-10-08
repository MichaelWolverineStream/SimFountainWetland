# SimFountainWetland

A small simulation game about aerating a wetland pond. The basin is a voxel diorama traced from an aerial photo, and every water voxel tracks its dissolved oxygen (DO). Run a baseline without a fountain, then place a pump and a sprayer and set the flow. The goal is to pass the oxygen target using as little energy as possible.

- **Engine:** Godot 4.7.2, .NET edition (desktop: macOS, Windows, Linux)
- **Runtime:** .NET 10
- **Languages:** C# for the simulation and the performance-critical nodes; GDScript for the UI, camera, placement and game flow

## Requirements

| Tool | Version | Notes |
|---|---|---|
| Godot **.NET** edition | 4.7.2 exactly | The standard (non-.NET) Godot cannot run C# scripts. The version must match `Godot.NET.Sdk/4.7.2` in [SimFountainWetland.csproj](SimFountainWetland.csproj). |
| .NET SDK | 10.0.x | Pinned by [global.json](global.json) (`10.0.100`, rolls forward to the latest feature band). |
| VS Code (optional) | | C# Dev Kit; godot-tools is optional. |

Install on macOS:

```sh
brew install --cask godot-mono       # installs /Applications/Godot_mono.app
brew install --cask dotnet-sdk       # or download .NET 10 from https://dotnet.microsoft.com
dotnet --list-sdks                   # should list 10.0.x
```

On Windows or Linux, download the **.NET** build of Godot 4.7.2 from <https://godotengine.org/download>.

Point `GODOT4` at the Godot .NET binary. The commands below and the VS Code launch configuration use it:

```sh
# macOS (add to ~/.zshrc)
export GODOT4=/Applications/Godot_mono.app/Contents/MacOS/Godot
# Linux
export GODOT4=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64
# Windows (PowerShell)
$env:GODOT4 = "C:\Tools\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe"
```

## Build and run

### From the command line

```sh
dotnet build SimFountainWetland.sln          # builds SimCore, the Godot game assembly and the tests
$GODOT4 --headless --path . --import         # first run only: imports assets into .godot/
$GODOT4 --path .                             # runs the game (scenes/main.tscn)
```

On startup the output shows `SimCore loaded on .NET 10.0.x` and the water-cell count. Run `dotnet build` again after changing any C# file. GDScript changes need no build.

### From the Godot editor

1. Open Godot .NET and import [project.godot](project.godot), or run `$GODOT4 --editor --path .`.
2. Press **F5** (Run Project). The editor builds the C# projects automatically. You can also build manually with the **Build** button (hammer icon, top right).

### From VS Code

`.vscode/` is git-ignored, so create these two files yourself to get build-and-play with **F5** and C# debugging.

`.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    { "label": "build", "command": "dotnet", "type": "process",
      "args": ["build", "${workspaceFolder}/SimFountainWetland.sln"],
      "problemMatcher": "$msCompile", "group": { "kind": "build", "isDefault": true } },
    { "label": "test", "command": "dotnet", "type": "process",
      "args": ["test", "${workspaceFolder}/tests/SimCore.Tests/SimCore.Tests.csproj"],
      "problemMatcher": "$msCompile", "group": "test" }
  ]
}
```

`.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    { "name": "Play (Godot .NET)", "type": "coreclr", "request": "launch",
      "preLaunchTask": "build", "program": "${env:GODOT4}",
      "args": ["--path", "${workspaceFolder}"], "cwd": "${workspaceFolder}" }
  ]
}
```

Start VS Code from a shell where `GODOT4` is set, so that `${env:GODOT4}` resolves.

### Exporting a standalone build

1. In the editor, install the **.NET** export templates for 4.7.2: **Editor → Manage Export Templates**.
2. Add a preset under **Project → Export** for your platform, then export.

The repository does not contain an `export_presets.cfg`.

## Testing

| What | Command |
|---|---|
| Unit tests (SimCore, xUnit, 28 tests) | `dotnet test tests/SimCore.Tests/SimCore.Tests.csproj` |
| Full game flow, headless | `$GODOT4 --headless --path . --script res://tools/smoke_test.gd -- 1500 2500` |
| Screenshots (overview + cross-section) | `$GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw` |
| GDScript parse check (any Godot 4.7) | `$GODOT4 --headless --path . --check-only --script res://scripts/main.gd` |

The smoke test plays the whole game in about a second:

1. Measures the baseline.
2. Clicks a pump into the deepest column and a sprayer near it.
3. Evaluates each flow rate given on the command line (in L/min).
4. Prints `PASS`/`FAIL`, the power and the 24 h statistics for each flow.

You can add these options after the flow rates:

- **Scenario:** `season=0..3` (Spring, Summer, Autumn, Winter), `wind=0..2` (Calm, Moderate, High), `rain=0/1`, `bloom=0/1`.
- **Layout:** `sprayer_distance=<cells>` (default 8).
- **Parameter overrides:** any `SimParamsResource` property as `Name=value`, for example `PumpZoneLpmPerRadius=150`.

## How to play

The game runs in five stages. The large button in the top bar always does the next step.

1. **Setup:** choose the season, wind, rain and algae bloom, then press **Run baseline**.
2. **Baseline:** the simulation fast-forwards without a fountain until the daily mean DO settles (up to 14 days).
3. **Fountain:**
   - Press **Place pump** and click a water column. The pump sits on the bottom of that column.
   - Press **Place sprayer** and click where the spray should land.
   - Set the flow with the LPM slider (0–3000 L/min). Head, power and the pump-zone ring update live.
   - Press **Evaluate**. If you changed the conditions, use **Re-measure baseline** first; your fountain layout is kept.
4. **Evaluating:** fast-forwards until the target has held for 3 consecutive days (up to 10 days).
5. **Results:** compares baseline and fountain and shows PASS/FAIL, kWh/day, ΔDO per kWh and your best passing kWh/day for the scenario. Choose **Keep tuning** or **New scenario**.

**Target:** a 24 h mean DO of at least 6.0 mg/L and at most 10 % of the water volume hypoxic (below 2 mg/L), held for 3 simulated days. The score is the energy used (kWh/day); lower is better.

### Controls

| Input | Action |
|---|---|
| Right mouse drag | Orbit the camera |
| Middle mouse drag | Pan |
| Mouse wheel | Zoom |
| Left click | Place the pump or sprayer (in placement mode) |
| Esc | Cancel placement |
| Pause / 1x / 4x / 16x | Simulation speed (1 tick = 1 simulated hour) |
| **Slice along X** + slider | Cut the diorama to see the DO stratification; **Flip kept side** shows the other half |

Voxel colours run from red (no oxygen) through yellow and green to blue (about 14 mg/L). The legend and the depth-profile bars are in the HUD.

## Simulation model

The model lives in [src/SimCore](src/SimCore). It is a pure C# library with no Godot dependency, so it can be unit-tested.

- **Grid:**
  - A tick is 1 hour.
  - A cell is 2 m × 0.25 m × 2 m (1 m³). It is drawn as a unit cube, which exaggerates depth 8×.
  - Water cells come from a flood fill of the GridMap basin. If the fill leaks out of the grid, the level is rejected.
- **Processes in each tick:**
  1. Photosynthesis, which depends on daylight and depth.
  2. Oxygen demand in the water column (BOD) and at the sediment (SOD).
  3. Reaeration at the surface, driven by wind. Water above saturation degasses.
  4. Rain mixing.
  5. Anisotropic diffusion.
- **Seasons:** each season sets the saturation level, how fast the biology runs and the day length.
- **Algae bloom:** increases photosynthesis, oxygen demand and light extinction.
- **Fountain:**
  - The pump draws water from the bottom of its pump zone and pushes that zone's columns downward.
  - The sprayer aerates the water and mixes it into its surface footprint.
  - The pump-zone radius grows with the flow: `1 + LPM / PumpZoneLpmPerRadius`.
- **Energy:** `P = ρ·g·Q·H / η`.
  - The head `H` is the spray height plus pipe friction.
  - The pipe length is the pump depth plus the horizontal distance from pump to sprayer, so placement affects the energy cost.

All rates are in [src/SimCore/SimConfig.cs](src/SimCore/SimConfig.cs). You can override them without recompiling: select [params/default_sim_params.tres](params/default_sim_params.tres) in the Godot inspector. Calibration results and open balance questions are in [_design/implementationPlan.md](_design/implementationPlan.md) (Phase 7).

## Project layout

```
project.godot, SimFountainWetland.csproj/.sln, global.json
src/SimCore/        simulation library (net10.0, no Godot references)
src/Game/           C# Godot nodes: SimulationNode, GridMapVoxelizer, WaterVoxelRenderer, SimParamsResource
tests/SimCore.Tests xUnit tests for SimCore
scenes/             main.tscn (game), level_wetland.tscn (generated GridMap diorama)
scripts/            GDScript: main (stages), hud, orbit_camera, placement_tool, fountain_visuals,
                    slice_controller, depth_profile, level_wetland
shaders/            do_voxel (DO colouring + slice), terrain_clip (terrain slice)
assets/             tiles.tres (MeshLibrary), do_gradient.tres, guides/aerial_photo.jpeg
params/             default_sim_params.tres
tools/              build_level.gd, smoke_test.gd, screenshot.gd
_design/            design notes and implementation plan (ignored by Godot)
```

## Editing the level

[tools/build_level.gd](tools/build_level.gd) generates [scenes/level_wetland.tscn](scenes/level_wetland.tscn) and [assets/tiles.tres](assets/tiles.tres). The level is traced from the aerial photo: about 96 × 64 × 14 cells, three islands, and a basin up to 2.5 m deep.

```sh
$GODOT4 --headless --path . --script res://tools/build_level.gd                        # regenerate
$GODOT4 --headless --path . --script res://tools/build_level.gd -- --preview /tmp/level.png  # plus a top-down preview
```

You can also edit the GridMap by hand in the editor. The `BasinSeed` marker and `water_level_y` on the level define the water body. Re-running the generator overwrites any hand edits.

## Troubleshooting

- **C# scripts fail to load, or the scene shows no water:** you opened the project with the standard Godot build. Use the **.NET** edition.
- **`Godot.NET.Sdk` restore or version error:** the SDK version in the csproj must equal your editor version (4.7.2).
- **`dotnet` picks the wrong SDK:** check `dotnet --list-sdks`. `global.json` requires a 10.0.x SDK.
- **"Simulation failed to load: … basin is not watertight":** the water flood fill escaped the grid. Close the gap in the GridMap, or lower `water_level_y`.

## License

MIT. See [LICENSE](LICENSE).
