# SimFountainWetland

A small simulation game about aerating a wetland pond. The basin is a voxel diorama traced from an aerial photo, and every water voxel tracks its dissolved oxygen (DO). Set a baseline, change something (the season, the weather, or the pump + sprayer fountains you place), and compare: a report shows what changed in the water, layer by layer, and what it costs in energy.

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
| Unit tests (SimCore, xUnit, 36 tests) | `dotnet test tests/SimCore.Tests/SimCore.Tests.csproj` |
| Full game flow, headless | `$GODOT4 --headless --path . --script res://tools/smoke_test.gd -- 1500 2500` |
| Screenshots (report, overview, oxygen, close-ups, night, cross-section) | `$GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw` |
| GDScript parse check (any Godot 4.7) | `$GODOT4 --headless --path . --check-only --script res://scripts/main.gd` |

The smoke test plays the whole game in a few seconds:

1. Sets a baseline with no fountains.
2. Clicks fountain units into the level (pump in deep water, sprayer nearby).
3. Compares each flow rate given on the command line (in L/min) against the baseline.
4. Prints the measured statistics and the change from the baseline for each flow.

It also checks the fountain list and info lines (add, select, move, remove, the unit limit), the report, the camera input (wheel, pinch, trackpad scroll, Option+drag, Home) and the scenery (props, ducks, critters, clouds, stars, lamps and fireflies at night, Nature as the start view and the water view toggle). Any failed check makes it exit with code 1.

The screenshot tool writes `<prefix>_report.png`, `_overview.png` (Nature view), `_oxygen.png`, `_closeup.png`, `_jetty.png`, `_field.png`, `_pond.png`, `_heron.png`, `_night.png` and `_slice.png`. It needs a window (not `--headless`).

You can add these options after the flow rates:

- **Scenario:** `season=0..3` (Spring, Summer, Autumn, Winter), `wind=0..2` (Calm, Moderate, High), `rain=0/1`, `bloom=0/1`.
- **Layout:** `units=<count>` (fountain units, default 1, at most 8), `sprayer_distance=<cells>` (default 8).
- **Environment comparison:** `compare_season=0..3` adds a run that keeps the fountains and only changes the season.
- **Parameter overrides:** any `SimParamsResource` property as `Name=value`, for example `PumpZoneLpmPerRadius=150`.

## How to play

The simulation always runs live: change the season, wind, rain or algae bloom, or add fountains, and watch the water respond. To measure the effect of a change, compare it with a baseline.

1. **Set baseline:** pick the conditions to compare against (for example Summer with no fountains) and press **Set baseline**. The simulation restarts from a fresh morning and fast-forwards until the daily mean DO settles (3 to 14 simulated days). The result goes into the **Baseline** card.
2. **Change something:** add or move fountains, change their flow, or change the environment (for example Summer → Autumn).
3. **Compare with baseline:** the new setup is measured the same way, and a report opens in the middle of the window.

The report shows both setups side by side, what changed between them, the headline effects (mean DO, hypoxic volume, bottom DO, energy), a depth-profile chart of the 24 h mean DO in each layer, and a table of all numbers with their differences. **Make this the new baseline** uses the comparison run as the next reference; **Show last report** in the Baseline card opens the report again. **Stop** cancels a measurement without recording anything.

### Fountains

You can place up to 8 fountain units. Each unit is a pump and a sprayer with its own flow.

- **Add fountain**, then click a water column for the pump (it sits on the bottom of that column), then click where the spray should land.
- Select a unit in the list, or click its pump or sprayer in the 3D view. **Move pump**, **Move sprayer** and **Remove** act on the selected unit; **Clear all** removes every unit.
- The flow slider (0–3000 L/min) sets the selected unit's flow. Its daily energy and the pump-zone ring update live; the line below shows how many units run, their total flow and their daily energy.

### Controls

| Input | Action |
|---|---|
| Mouse wheel, trackpad pinch or two-finger scroll, `+` / `-` | Zoom the 3D view |
| Right mouse drag, Option (Alt) + left drag, Q / E | Orbit the camera |
| R / F | Tilt the camera |
| Middle mouse drag, Shift + left drag, Shift + two-finger scroll, WASD or arrow keys | Pan |
| Home | Reset the view |
| V | Switch the water between **Nature** (pond colours, the default) and **Oxygen** (DO colours) |
| Left click | Place a pump or sprayer (in placement mode), or select the unit at that spot |
| Esc | Cancel placement, or close the report |
| Pause / 1x / 4x / 16x | Simulation speed (1 tick = 1 simulated hour) |
| **Slice along X** + slider | Cut the diorama to see the DO stratification; **Flip side** shows the other half |

The game starts in **Nature** view, which shows the pond as water, darker where it is deeper. In **Oxygen** view, colours run from red (no oxygen) through yellow and green to blue (about 14 mg/L). From above, the water surface shows the average DO of each water column, blended smoothly between columns; slice the diorama to see the DO of every voxel. The legend and the depth-profile bars are in the HUD.

The **UI size** menu (Small, Medium, Large, Extra large) scales only the HUD. Your choice is saved in `user://settings.cfg`. On high-DPI screens the window opens sized to the display.

The scene follows the simulated clock. The sun and sky change through the day; at night the moon and stars come out, the path lamps glow and fireflies drift over the water. Clouds drift past with the wind, and trees, reeds and grass sway harder when it is windy. Trees, reeds, flowers, lilies, wheat fields, hay bales, fences, benches, lamp posts, a signpost and a wooden jetty are placed around the level when the game starts. A family of ducks swims around the fountains; herons fish in the shallows, frogs hop between lily pads, turtles sun themselves on shore rocks, a fish leaps now and then, and butterflies and dragonflies flutter by day.

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
scripts/            GDScript: main (live play and measurements), hud, report_panel + profile_compare
                    (comparison report), orbit_camera, placement_tool, fountain_visuals +
                    fountain_unit_visual, slice_controller, depth_profile, level_wetland, level_decor
                    (props), critters, ducks, sky_details (clouds, stars), day_night,
                    mesh_kit (procedural low-poly meshes)
shaders/            do_voxel (DO / nature colouring + slice), terrain_clip (terrain slice), decor (props,
                    sway, wing flap), particle (spray, splash, fireflies, foam), cloud, star, grid_floor,
                    slice_clip.gdshaderinc
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
$GODOT4 --headless --path . --script res://tools/build_level.gd -- --tiles-only          # restyle tiles, keep the level
```

The tile look (colours, bevels, grass tufts) is set by `TILE_STYLES` in the generator. `--tiles-only` rewrites only `tiles.tres`.

Scenery is not stored in the GridMap; the voxelizer treats every GridMap cell as solid. [scripts/level_decor.gd](scripts/level_decor.gd) scatters it at startup from the top tile of each column. Change `random_seed` or `tree_spacing` on the `Decor` node to vary it.

You can also edit the GridMap by hand in the editor. The `BasinSeed` marker and `water_level_y` on the level define the water body. Re-running the generator overwrites any hand edits.

## Troubleshooting

- **C# scripts fail to load, or the scene shows no water:** you opened the project with the standard Godot build. Use the **.NET** edition.
- **`Godot.NET.Sdk` restore or version error:** the SDK version in the csproj must equal your editor version (4.7.2).
- **`dotnet` picks the wrong SDK:** check `dotnet --list-sdks`. `global.json` requires a 10.0.x SDK.
- **"Simulation failed to load: … basin is not watertight":** the water flood fill escaped the grid. Close the gap in the GridMap, or lower `water_level_y`.

## License

MIT. See [LICENSE](LICENSE).
