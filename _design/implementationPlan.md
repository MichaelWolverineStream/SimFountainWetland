# Implementation Plan: SimFountainWetland V1

Godot 4.7 (.NET edition) + .NET 10. Static voxel diorama of the wetland in `aerial_photo.jpeg`; dissolved-oxygen (DO) cellular simulation in a pure C# library; GDScript for UI, camera, placement and game flow. The player runs a no-fountain baseline, places a pump + sprayer, sets throughput (LPM) and tries to pass the DO target with the least energy.

Source documents: `initial.md` (idea), `projectPlan.md` (initial plan), `game_visual_mockup.jpeg`, `aerial_photo.jpeg`.

---

## 1. Review of the initial plan

| # | Issue in `projectPlan.md` | Resolution |
|---|---|---|
| 1 | "Two central islands" | Photo and mockup show **three** islands. |
| 2 | Uses Z for depth | Godot is **Y-up**. Index = `x + SX*(z + SZ*y)`. |
| 3 | No units for tick / voxel, so LPM is not connected to the sim | **1 tick = 1 simulated hour**. **1 cell = 2 m × 0.25 m × 2 m = 1 m³ = 1000 L**, rendered as a 1-unit cube (8× vertical exaggeration). |
| 4 | "Average DO with neighbours" homogenises far too fast | Explicit **anisotropic diffusion** `D_h = 0.10`, `D_v = 0.01`, double buffer, no-flux boundaries (solid neighbour → self). Stability: `4·D_h + 2·D_v ≤ 1`. |
| 5 | Flat surface DO addition; `DO_max` hard clamp prevents algae supersaturation | Deficit-driven reaeration `k·(DO_sat − DO)` (degasses when supersaturated); only hard cap is 20 mg/L. |
| 6 | "Constant fractional decay −0.05" mixes models and can go negative | First-order water-column BOD + sediment oxygen demand (SOD) on bed-contact cells scaled by `DO/(DO+K)`. Depth effect emerges naturally. |
| 7 | Temperature only sets the ceiling | Season also scales biological rates (θ) and photoperiod. |
| 8 | `Efficiency = AvgDO / Energy` undefined at 0 energy, rewards baseline DO; no energy formula | Pass/fail gate, then minimise kWh/day. `P = ρ·g·Q·H / η`, `H = spray height + pipe friction` (a submerged intake adds no static head; friction `f·L·(LPM/1000)²` with `L` = pump depth + horizontal pump–sprayer distance makes placement matter). Also show ΔDO per kWh vs baseline. |
| 9 | Fountain transfer and convection underspecified | Withdraw → spray aeration `DO_out = DO_in + E·(DO_sat − DO_in)` → mix into surface footprint; pump-zone downward advection + vertical-mixing boost. Mass is abstracted (documented). |
| 10 | Shader uses `VERTEX.x` in `fragment()` | In Godot 4 that is view space. Use the per-instance origin `MODEL_MATRIX[3]` in `vertex()` + global uniform `slice_x`, snapped to whole cells. |
| 11 | Per-instance `set_instance_color` per tick | Write the whole `MultiMesh.Buffer` from C#; raw DO in `INSTANCE_CUSTOM.r`, gradient lookup in the shader. |
| 12 | No game flow, total DO readout, camera, tests | Stages Baseline → Fountain → Results; total DO (kg); orbit camera; xUnit tests. |
| 13 | Rendering after the DO model | Debug voxel rendering comes in the integration phase so the model can be verified visually. |

## 2. Decisions

- **Platform:** desktop only (macOS / Windows / Linux). No web export.
- **Languages:** C# for simulation core (`src/SimCore`, no Godot references) and performance-critical Godot nodes (`src/Game`); GDScript for UI, camera, placement and flow. GDScript calls C# members by their PascalCase names.
- **Runtime:** .NET 10 (`global.json` pins SDK 10.0.x; every project targets `net10.0`). Godot 4.7 requires .NET 8+.
- **Terrain:** hand-built `GridMap`. Water cells = flood fill from a `BasinSeed` marker through empty cells with `y ≤ water_level_y`; reaching the grid boundary is a leak error.
- **Scoring:** gate = 24 h mean grid DO ≥ 6.0 mg/L **and** 24 h mean hypoxic (< 2 mg/L) volume ≤ 10 %, sustained for 3 consecutive simulated days. Score = kWh/day (lower is better). Also display ΔDO per kWh vs baseline.
- **Algae:** day/night cycle — photosynthesis by day, respiration always; a bloom amplifies both.
- **Out of scope for V1:** photo upload / colouring / terrain generation, user-adjustable depth, multiple fountains, real hydrodynamics, separate temperature field, save/load, web export.

## 3. Project layout

```
global.json
project.godot
SimFountainWetland.csproj        Godot.NET.Sdk, net10.0, references SimCore
SimFountainWetland.sln
src/
  SimCore/                       pure C# class library (.gdignore)
    SimCore.csproj
    Int3.cs, VoxelGrid.cs, SimConfig.cs, EnvironmentState.cs,
    DOModel.cs, FountainModel.cs, EnergyModel.cs, SimStats.cs, Scoring.cs
  Game/                          C# Godot nodes
    SimulationNode.cs, GridMapVoxelizer.cs, WaterVoxelRenderer.cs, SimParamsResource.cs
tests/                           (.gdignore)
  SimCore.Tests/                 xUnit, net10.0
scenes/    main.tscn, level_wetland.tscn (generated)
scripts/   main.gd, orbit_camera.gd, placement_tool.gd, fountain_visuals.gd, slice_controller.gd,
           hud.gd, depth_profile.gd, level_wetland.gd
shaders/   do_voxel.gdshader, terrain_clip.gdshader
assets/    tiles.tres (generated MeshLibrary), do_gradient.tres, guides/aerial_photo.jpeg
params/    default_sim_params.tres
tools/     build_level.gd (level generator), smoke_test.gd, screenshot.gd
_design/   (.gdignore)
```

## 4. Phases

Dependencies: Phase 0 blocks everything. Phases 1 and 2 run in parallel. Phase 3 needs 1 + 2. Phases 4 and 5 run in parallel after 3. Phase 6 needs 3–5. Phase 7 needs all.

### Phase 0 — Toolchain and skeleton

1. Prerequisites: Godot 4.7 **.NET edition** (`brew install --cask godot-mono`), .NET 10 SDK (`dotnet --list-sdks` shows 10.0.x), VS Code C# Dev Kit, optional godot-tools. Set `GODOT4` to the .NET editor binary.
2. `global.json`: `sdk.version` 10.0.100, `rollForward: latestFeature`.
3. `project.godot` at repo root (Forward+). Add `_design/.gdignore`. Copy `aerial_photo.jpeg` to `assets/guides/`.
4. `SimFountainWetland.csproj`: `Sdk="Godot.NET.Sdk/<exact editor version>"`, `TargetFramework net10.0`, `Nullable enable`, `RootNamespace SimFountainWetland`, `Compile Remove` for `src/SimCore/**` and `tests/**`, `ProjectReference` to `src/SimCore/SimCore.csproj`.
5. `src/SimCore/SimCore.csproj`: class library, `net10.0`, `Nullable enable`, no Godot references (own `Int3` instead of `Vector3I`). Add `.gdignore`.
6. `tests/SimCore.Tests/`: xUnit, `net10.0`, references SimCore. Add `tests/.gdignore`.
7. Solution containing all three projects.
8. `.gitignore`: add `bin/`, `obj/`, `TestResults/`, `.vs/`, `*.user`.
9. Folders: `scenes/`, `scripts/`, `shaders/`, `assets/`, `params/`, `src/Game/`.
10. `project.godot`: shader globals `slice_x` (float, 1e6) and `slice_enabled` (bool, false); input actions `cam_orbit` (RMB), `cam_pan` (MMB), `cam_zoom_in` / `cam_zoom_out` (wheel), `place` (LMB), `cancel` (Esc); window 1600×900.
11. `.vscode/tasks.json` (`dotnet build`) and `.vscode/launch.json` (coreclr, program `${env:GODOT4}`).
12. Smoke: `SimCore.Info.RuntimeVersion`; stub `src/Game/SimulationNode.cs` in `scenes/main.tscn` prints it in `_Ready`; one xUnit test.

**Exit:** `dotnet build` succeeds; `dotnet test` passes; running the project in Godot prints a 10.0.x runtime.

### Phase 1 — Simulation core (`src/SimCore`)

1. **`VoxelGrid`**
   - Dimensions `(SX, SY, SZ)`, solid mask, compact water arrays (N water cells), grid↔compact index map.
   - 6-neighbour table (`int[N*6]`), solid neighbour → self (no-flux).
   - Per-cell flags: surface, bed-contact face count (below + 4 sides), depth in metres; per-column top/bottom water cell.
   - `FromSolidMask(mask, seed, waterLevelY)`: 6-connected flood fill from seed through non-solid cells with `y ≤ waterLevelY`; reaching the grid boundary → leak error.
2. **`SimConfig`** defaults:
   - Cell: 2.0 m × 0.25 m × 2.0 m. Tick: 1 h.
   - Seasons (DO_sat mg/L / θ / photoperiod h): Spring 10 / 1.0 / 13; Summer 8 / 1.6 / 15; Autumn 10 / 0.9 / 11; Winter 14 / 0.4 / 9.
   - Wind multiplier: Calm 0.5, Moderate 1.0, High 1.5.
   - `k_surf` 0.08; `D_h` 0.10; `D_v` 0.01.
   - Rain: `D_v × 8`; top two layers relax toward DO_sat at 0.15/tick.
   - `k_bod` 0.004/tick; SOD 0.15 mg/L per tick per bed-face weight, half-saturation 1.0 mg/L. Bed weight = 1 for a floor face + `CellSizeY/CellSizeXZ` (0.125) per side face, so the 8× vertical exaggeration does not inflate wall contact.
   - Photosynthesis `P_max` 0.25 mg/L/tick; light extinction 1.2 /m.
   - Bloom: `P_max × 3`, `k_bod × 4` (+300 %), extinction × 3.
   - DO cap 20; initial DO = 0.9 × DO_sat.
   - Fountain: spray height 2 m, aeration efficiency E 0.7, pump efficiency η 0.5, pipe friction 0.04 m per m at 1000 LPM, LPM 0–3000.
   - Scoring: hypoxia 2.0, target 6.0, max hypoxic fraction 0.10, window 24 ticks, 3 days sustained.
3. **`EnvironmentState`**: season, wind, rain, bloom, clock (day, hour). Light = `sin(π·(h − sunrise)/photoperiod)` during daylight, else 0; sunrise = 12 − photoperiod/2.
4. **`DOModel.Step()`** operator order:
   1. Sync pump-zone `D_v` multipliers if the fountain changed.
   2. Biology: `+P_max·light·exp(−k_ext·depth)`; `−k_bod·θ·DO`; bed cells `−SOD·θ·bedWeight·DO/(DO+K)`.
   3. Surface reaeration `k_surf·wind·(DO_sat − DO)`; rain relaxation on top two layers.
   4. Fountain (if active), then clamp to `[0, cap]`.
   5. Diffusion (rain and pump-zone multipliers on `D_v`; per-link coefficient `min(D_v·max(m_i, m_j), (1 − 4·D_h)/2)` keeps it symmetric and stable).
   6. Stats, then advance the clock.
5. **`FountainModel`**: pump cell, sprayer cell, LPM → voxels/tick `V = LPM·60/1000`; head `H` = spray height + pipe friction; pump-zone radius `1 + LPM/100` (calibrated, was `/750`); spray footprint radius `1 + LPM/1000`.
   - Withdraw: DO_in = mean of pump-zone bottom cells.
   - Pump zone columns: upwind downward shift by fraction `f = clamp(V / zoneColumns, 0, 1)`.
   - Spray: `DO_out = DO_in + E·(DO_sat − DO_in)`; mix into footprint surface cells with fraction `g = clamp(V / footprintCells, 0, 1)`.
   - Pump zone `D_v × 5`.
6. **`EnergyModel`**: `P[W] = 1000·9.81·(LPM/60000)·H / η`; kWh per tick = P/1000 · 1 h.
7. **`SimStats` / `Scoring`**: mean / min / max DO, total DO kg (`Σ DO·1000 L / 1e6`), hypoxic fraction, per-layer means, kWh; rolling 24 h means; pass streak; kWh/day; ΔDO/kWh vs baseline.
8. **Tests** (see Verification).

### Phase 2 — GridMap diorama (parallel with Phase 1)

1. `scenes/tiles.tscn`: 1×1×1 box tiles — Grass, Soil, Mud/Bed, IslandGrass, Path, Hedge — using `terrain_clip.gdshader`. Export as `assets/tiles.meshlib`.
2. `scenes/level_wetland.tscn`: `GridMap` (cell size 1,1,1), exported `water_level_y`, `BasinSeed` Marker3D, `_Guides` node with a plane textured with the aerial photo for tracing (freed at runtime).
3. Author ~96 × 64 × 14 cells; basin ≤ 10 cells deep (2.5 m); three islands; soil band visible on diorama edges. Side ponds are decorative and not connected to the seed.

**As built:** `tools/build_level.gd` (headless `SceneTree` script) generates both `assets/tiles.tres` (MeshLibrary: Grass, Meadow, Field, Soil, Mud, Island, Path, Hedge, Road, Pond — box meshes with `terrain_clip` materials) and `scenes/level_wetland.tscn` from a shape description traced from the aerial photo. Re-run with `Godot --headless --path . --script res://tools/build_level.gd` (add `-- --preview /tmp/level.png` for a top-down preview). The generated GridMap can be hand-edited afterwards; re-running the tool overwrites it.

### Phase 3 — Integration

1. `src/Game/GridMapVoxelizer.cs`: `GetUsedCells()` → bounding box → solid mask → `VoxelGrid.FromSolidMask`. Report leaks clearly.
2. `src/Game/SimulationNode.cs`: owns grid + model; child `Timer` 0.5 s; speed 0/1/4/16 ticks per timeout; fast-forward (24 ticks per frame) with progress; API `SetEnvironment`, `SetPump`, `SetSprayer`, `SetLpm`, `ResetDO`, `GetStats`, `GetColumnTop`, `GetColumnBottom`; signals `TickCompleted`, `BaselineProgress`.
   - **As built:** methods `SetSpeed`, `StepTicks`, `StartFastForward`, `StopFastForward`, `ResetSimulation`, `ResetScoring`, `IsSteady`, `SetEnvironment`, `IsWaterColumn`, `GetColumnTopCenter`, `GetColumnBottomCenter`, `PlacePump`, `PlaceSprayer`, `SetLpm`, `ClearFountain`, `GetFountainInfo`, `GetStats`, `GetLayerMeans`, `GetGridOrigin`, `GetGridSize`, `GetWaterSurfaceY`; signals `TicksAdvanced`, `DayCompleted(Dictionary)`, `FastForwardProgress(done, total)`, `FastForwardFinished`. Columns use GridMap coordinates; the Level sits at the world origin.
3. `src/Game/WaterVoxelRenderer.cs` (`MultiMeshInstance3D`): set `TransformFormat` and `UseCustomData = true` **before** `InstanceCount`; write transforms once; per tick overwrite custom-data floats in a cached `float[]` and assign `Multimesh.Buffer`.
4. `shaders/do_voxel.gdshader`: `INSTANCE_CUSTOM.r` → `GradientTexture1D` (red → orange → yellow → green → cyan).
5. `scripts/orbit_camera.gd`: RMB orbit, MMB pan, wheel zoom, clamped pitch.
6. `scenes/main.tscn`: level, simulation, renderer, camera, light, debug stats label.

**Milestone:** baseline runs visibly and stratification develops.

### Phase 4 — Fountain placement and visuals (parallel with Phase 5)

1. `scripts/placement_tool.gd`: Pump / Sprayer modes; camera ray ∩ `Plane(UP, water_surface)` → column; ignore non-water columns; pump → bottom water cell, sprayer → top water cell; re-placeable.
2. `scripts/fountain_visuals.gd`: pump and sprayer meshes, pipe cylinder, `GPUParticles3D` spray arc, pump-zone ring.

### Phase 5 — Slice view and legend (parallel with Phase 4)

1. Water and terrain shaders: per-instance origin from `MODEL_MATRIX[3]` passed as a varying; discard when `slice_enabled && origin.x > slice_x`. Fallback: per-fragment world position with slice snapped to cell boundary + ε.
   - **As built:** the vertex shader collapses cut instances to a point (no `discard` cost); a third global `slice_flip` keeps the other side. The slice plane sits on a cell boundary so column `x` stays visible.
2. `scripts/slice_controller.gd`: slider in whole cells, flip toggle, translucent orange plane marker; sets globals via `RenderingServer.global_shader_parameter_set`. **As built:** orange frame instead of a filled plane, so the cut face stays readable.
3. Colour legend 0–14 mg/L.

### Phase 6 — UI, game flow, scoring

1. `scripts/main.gd` state machine: SETUP → BASELINE_RUN → FOUNTAIN → RESULTS. Baseline runs until the 24 h mean changes < 0.01 mg/L per day or 14 days; changing the environment afterwards marks the baseline stale.
   - **As built:** an extra EVALUATING stage fast-forwards up to 10 days and stops as soon as the target holds for 3 days. Changing the fountain or environment resets the pass streak. A stale baseline can be re-measured; the fountain layout is remembered and restored. Evaluating with no fountain is allowed (winter can pass at 0 kWh/day). Results track the best passing kWh/day per scenario.
2. `scenes/hud.tscn` + `scripts/hud.gd`:
   - Top bar: stage, Day/Hour, Pause / 1× / 4× / 16×, Reset.
   - Environment: Season, Wind, Rain, Algae.
   - Fountain: Place Pump / Place Sprayer, LPM slider (0–3000, step 50), head (m), power (kW), kWh today / total.
   - Stats: mean, min, total kg, hypoxic %, 24 h mean, depth-profile bars.
   - Results panel: baseline vs fountain, PASS/FAIL, kWh/day, ΔDO/kWh.
   - **As built:** no `hud.tscn`; `hud.gd` is a `CanvasLayer` on `main.tscn` that builds its controls in code and only emits intent signals. Adds a cross-section panel, a colour legend and a target summary.
3. Optional: sun angle follows the simulated hour. **Done** (`main.gd::_update_sun`).

### Phase 7 — Balancing

Tune `params/default_sim_params.tres` (`SimParamsResource` → `SimConfig`) to these targets:

| Scenario | Expected |
|---|---|
| Winter / Moderate, no fountain | Passes |
| Summer / Calm, no fountain | Mean ≈ 4–5, bottom < 1, hypoxic ≈ 30 %, fails |
| Summer + Bloom | Afternoon surface supersaturation, night crash |
| Summer / Calm + 1000–2000 LPM at deepest point | Passes |

Main levers: pump-zone radius and its `D_v` multiplier (destratification is the fountain's main real-world benefit).

Phase 1 calibration notes (58 × 38 × 10 box, 22k cells, Summer / Calm, 14 days, pump + sprayer at centre):

- Baseline: mean 4.2, bottom 0.05, hypoxic 30 % — matches the table.
- Fountain benefit scales with pump-zone **area**. Radius `1 + LPM/750`: 3000 LPM → mean 4.5 (fails). `1 + LPM/250`: 2000 LPM → 4.9, 3000 → 5.5. `1 + LPM/150`: 3000 → 6.5 (passes).
- `D_v` multiplier (5 vs 30), extra entrained circulation and a pump-zone surface-reaeration boost have **negligible** effect: the zone is already well mixed, and the summer surface is supersaturated by photosynthesis, so the gain comes from keeping photosynthetic O₂ in the water column instead of degassing it.
- Therefore tune `PumpZoneLpmPerRadius` (likely 150–250) on the real level first, then `TargetMeanDo` / rates if needed.
- Release build: ~0.2 ms per tick at 22k cells.

Real-level calibration (7623 water cells; pump in the deepest column, sprayer 1 cell away; `tools/smoke_test.gd`). `PumpZoneLpmPerRadius` is now **100**:

| Scenario | Baseline mean / hypoxic | Lowest passing flow |
|---|---|---|
| Summer / Calm | 4.00 / 33 % | 2500 LPM (2.5 kW, ~61 kWh/day); 2000 LPM just fails (11 % hypoxic) |
| Spring / Moderate | 5.75 / 21 % | 1500 LPM |
| Autumn / Moderate | 5.66 / 21 % | 1500 LPM |
| Winter / High | 10.96 / 1 % | none needed |
| Summer / Calm + Bloom | 2.55 / 57 % | none up to 3000 LPM (4.66 mg/L): the hard scenario |

Pipe length matters: a sprayer 8 cells from the pump needs 3.2 kW instead of 1.8 kW at 2000 LPM. Open questions: the spray position barely changes DO (only the pump zone does), and bloom may be too hard.

## 5. Verification

1. **Phase 0:** `dotnet build SimFountainWetland.sln`; `dotnet test`; Godot run prints `.NET 10.0.x`.
2. **xUnit (SimCore):**
   - Index round-trip.
   - Diffusion without sources conserves total DO (1e-4 relative).
   - No flux into solids.
   - Reaeration converges to DO_sat; supersaturated water degasses.
   - SOD never makes DO negative.
   - Flood fill: leak detected on an open basin; correct count on a simple bowl.
   - Summer / Calm, 7 days: surface mean ≥ bottom mean + 2 mg/L.
   - Bloom: surface DO at 15:00 > at 05:00.
   - Fountain raises bottom mean DO after 3 days.
   - Energy: 1000 LPM, H = 5 m, η = 0.5 → 1.635 kW ± 0.01.
   - Scoring gate on synthetic series.
   - Determinism: identical inputs → identical arrays.
3. **Performance:** one tick on ~25k water cells < 3 ms (Release). Otherwise move ticks to a worker thread with double buffering.
4. **Manual:** level loads and reports water-cell count; stratification forms; slice is a clean cut; placement snaps; kW responds to depth and LPM; PASS/FAIL updates; 60 FPS at 16×.
5. **Automated in-engine (Godot .NET):**
   - `$GODOT4 --headless --path . --script res://tools/smoke_test.gd -- 1000 2000 3000 [season=1 wind=0 bloom=0 sprayer_distance=1 PumpZoneLpmPerRadius=100]` runs the whole game flow and prints the results.
   - `$GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw` saves an overview and a cross-section screenshot.

## 6. Further considerations

1. `Godot.NET.Sdk` version must equal the installed editor version.
2. Adjustable spray height (more aeration vs more head/energy) — candidate for V1.1.
3. A horizontal (Y) slice would make bottom hypoxia visible from above.
4. If hand-building 96 × 64 is too slow, 64 × 48 preserves gameplay.
