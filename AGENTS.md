# Agent guide: SimFountainWetland

Godot 4.7.2 **.NET** game: a voxel wetland diorama whose water cells track dissolved oxygen (DO). The player sets a baseline, changes the environment or places up to 8 pump+sprayer fountain units, and compares the two in a report. There is no pass/fail win condition (it was removed on purpose; don't reintroduce targets, streaks or verdicts).

- Player-facing docs, controls, test options: [README.md](README.md)
- Design history and calibration notes (Phases 0-9): [_design/implementationPlan.md](_design/implementationPlan.md)

## Build and test

Set `GODOT4=/Applications/Godot_mono.app/Contents/MacOS/Godot` (macOS). The non-.NET `/Applications/Godot.app` cannot run the C# nodes.

| Purpose | Command |
|---|---|
| Build (needed after any C# change, before running Godot) | `dotnet build SimFountainWetland.sln` |
| Unit tests (SimCore, xUnit) | `dotnet test tests/SimCore.Tests/SimCore.Tests.csproj` |
| Import assets (first run, or after adding files) | `$GODOT4 --headless --path . --import` |
| GDScript parse check | `$GODOT4 --headless --path . --check-only --script res://scripts/<file>.gd` |
| Headless game-flow smoke test (exits 1 on any failed check) | `$GODOT4 --headless --path . --script res://tools/smoke_test.gd -- 2500 sprayer_distance=1` |
| Screenshots (needs a window, not `--headless`) | `$GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw` |
| Regenerate tiles only | `$GODOT4 --headless --path . --script res://tools/build_level.gd -- --tiles-only` |

Useful smoke variants: `-- 1500 units=3`, `-- 0 compare_season=2 units=8`. At exit Godot prints `ParticlesShaderRD ... never freed` / leaked RID errors; these are benign.

Before finishing a change: build, unit tests, `--check-only` on every changed `.gd`, the smoke test, and for visual work a screenshot run that you actually look at.

## Architecture

- [src/SimCore](src/SimCore): pure C# (net10.0, no Godot references). `DOModel` steps the DO field (1 tick = 1 simulated hour); `FountainSet` holds `FountainModel` units by `Id`; `DailyStats` builds a `DaySummary` (24 h means, min/max, per-layer profiles) and detects settling with `IsSteady`. All rates live in `SimConfig`, overridable via [params/default_sim_params.tres](params/default_sim_params.tres) (`SimParamsResource`).
- [src/Game](src/Game): Godot C# nodes. `SimulationNode` is the only bridge to GDScript (PascalCase API: `AddFountain`, `PlaceFountainPump(id, x, z)`, `SetFountainLpm`, `GetFountains`, `GetFountainTotals`, `GetStats`, `GetLastDay`, `StartFastForward`, `ResetSimulation`, `IsSteady`, ...; signals `TicksAdvanced`, `DayCompleted`, `FastForwardProgress`, `FastForwardFinished`).
- [scripts/main.gd](scripts/main.gd) owns the game flow: `Mode { LIVE, MEASURE_BASELINE, MEASURE_COMPARISON }`. A measurement resets the sim, fast-forwards until settled (3-14 days) and stores a snapshot dictionary (`_snapshot()`); comparisons open the report. Fountain add/move/select logic also lives here.
- [scripts/hud.gd](scripts/hud.gd) is built entirely in code, only displays data and emits intent signals. The report is [scripts/report_panel.gd](scripts/report_panel.gd) with the chart in [scripts/profile_compare.gd](scripts/profile_compare.gd).
- [scripts/placement_tool.gd](scripts/placement_tool.gd) only ray-casts and emits `placed` / `column_clicked` / `cancelled`; it never calls the simulation's placement API.
- 3D presentation: `fountain_visuals.gd` (manager) + `fountain_unit_visual.gd` (one per unit), `level_decor.gd` (props), `critters.gd`, `ducks.gd`, `sky_details.gd` (clouds, stars), `day_night.gd` (`night_changed`, `daylight_changed`), `slice_controller.gd`, all wired in [scenes/main.tscn](scenes/main.tscn) and `main.gd`.
- [tools/build_level.gd](tools/build_level.gd) generates `scenes/level_wetland.tscn` and `assets/tiles.tres`; re-running it overwrites hand edits.

## Conventions and gotchas

- **Versions:** `Godot.NET.Sdk/4.7.2` in the csproj must equal the editor version. The `.sln` must stay a classic `.sln`. The Godot csproj excludes `src/SimCore/**` and `tests/**` via `DefaultItemExcludes` and has no ImplicitUsings (add `using System;` in `src/Game`).
- **C# from GDScript:** call members by their PascalCase names and connect C# signals with `node.connect("Name", callable)`.
- **Coordinates:** the level sits at the origin, so world x/z equal GridMap column indices. Use `GetWaterSurfaceY()` and `GetColumnTop/BottomCenter()` instead of hard-coding heights.
- **Never put scenery in the GridMap:** the voxelizer treats every GridMap cell as solid. Props and animals are spawned at runtime from the top tile of each column.
- **Slicing:** every new 3D thing must honour the cross-section. Use `MeshKit.decor_material()` / `MeshKit.particle_material()` or include [shaders/slice_clip.gdshaderinc](shaders/slice_clip.gdshaderinc). Small instances are cut by their origin (`MODEL_MATRIX[3].x`); large meshes set `clip_pixels` (+ `clip_rect`) on the particle shader. Shader globals: `slice_x`, `slice_enabled`, `slice_flip`, `water_view` (0 oxygen, 1 nature; starts at 1).
- **Procedural meshes:** build them with [scripts/mesh_kit.gd](scripts/mesh_kit.gd); vertex colours must be stored linear (MeshKit converts), and vertex alpha 1 marks parts tinted by `INSTANCE_CUSTOM`. Prefer one MultiMesh per prop type and keep scatter deterministic (seeded RNG).
- **HUD:** keep theme-driven sizes (base font 20) and `MOUSE_FILTER_STOP` on panels so clicks don't reach the 3D view; custom themes need explicit CheckBox icons or they vanish on dark panels.
- **Tests as contract:** `tools/smoke_test.gd` reaches into private members (`main._start_measure`, `main._on_add_fountain`, `hud._compare_button`, `hud._report._content`, `decor._fireflies`, `sky._stars`, `critters._butterflies`, node names like `LampBulbs`, ...). When renaming any of these, update the smoke test and [tools/screenshot.gd](tools/screenshot.gd) too, and add a `_check(ok, "what")` for new behaviour.
- **Style:** short comments only where the code can't speak for itself; keep public APIs of the HUD and `SimulationNode` stable unless the task requires a change.
- **Docs:** when behaviour changes, update [README.md](README.md) and add a phase note to [_design/implementationPlan.md](_design/implementationPlan.md).
