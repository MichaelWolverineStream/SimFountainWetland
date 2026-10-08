
### Phase 1: Foundation and Godot Architecture

Establish the core engine structures using Godot 4.

* **Engine & Scripting:** Utilize Godot 4 and GDScript.
* **Data Structure:** Implement a flattened 1D array (`PackedByteArray` or `PackedFloat32Array`) managed by a custom Godot Node to represent the 3D voxel grid. This decouples the Cellular Automaton (CA) logic from the scene tree.
* **Tick System:** Use a `Timer` node set to a fixed interval (e.g., 0.5 seconds) to trigger the simulation calculations independently from `_process(delta)`.

### Phase 2: Static Terrain Construction (V1)

Defer dynamic terrain generation. V1 will feature a fixed, pre-authored diorama based directly on the reference visual.

* **Level Design:** Manually construct the level boundaries, the two central islands, and the water basin using Godot's `GridMap` or static meshes.
* **Voxel Initialization:** Generate the starting voxel array based on the static basin's bounding box. Flag solid terrain blocks (islands, floor) as `is_land = true` so they are ignored by the fluid CA.

### Phase 3: Dissolved Oxygen (DO) Research & Game Algorithms

Real-world DO dynamics are complex; for game purposes, they must be abstracted into deterministic, performant mathematical rules.

**Normal Behavior & Concentrations (3a, 3c)**

* *Research:* DO enters water from the atmosphere and photosynthesis, and is consumed by respiration and decay. Normal concentrations range from $0$ mg/L (anoxic) to roughly $14$ mg/L. Healthy levels are $5$ to $8$ mg/L.
* *Game Algorithm:* DO is represented as a float from $0.0$ to a variable $DO_{max}$. The game's target win state requires maintaining an average of $6.0$ mg/L.

**Gradients & Transfer Rates (3b, 3d)**

* *Research:* Natural wetlands are stagnant. Surface water is highly oxygenated, but DO diffuses downward very slowly (reaeration coefficients are often $< 1.0 \text{ day}^{-1}$). The bottom is frequently hypoxic due to high biological oxygen demand (BOD) from decaying organic matter.
* *Game Algorithm (Diffusion & Decay):* Each tick, a voxel averages its DO with its immediate neighbors. To simulate bottom hypoxia, apply a constant fractional decay multiplier (e.g., $-0.05$ mg/L per tick) that increases in severity at deeper Z-levels.

**Temperature (3f)**

* *Research:* Water temperature dictates the maximum solubility of oxygen. Cold water holds more DO; warm water holds less.
* *Game Algorithm:* Temperature strictly sets the $DO_{max}$ ceiling. Summer caps $DO_{max}$ at $8.0$ mg/L; Winter caps it at $14.0$ mg/L.

**Wind (3e)**

* *Research:* Wind creates ripples, increasing surface area and mechanical mixing, which drives atmospheric transfer.
* *Game Algorithm:* Apply a base DO addition to the topmost water voxels each tick. The `Wind` setting acts as a direct multiplier to this addition rate (e.g., High Wind = $1.5 \times$ base surface transfer).

**Rain (3g)**

* *Research:* Rain drops are fully saturated with oxygen and physically agitate the surface, causing deep mixing.
* *Game Algorithm:* When active, rain adds a flat DO bonus to the top two Z-layers and temporarily increases the downward diffusion rate for the entire grid, overriding normal stratification.

**Algae Blooms (3h)**

* *Research:* Algae causes extreme diurnal shifts (supersaturation during sunny days, severe depletion at night via respiration). Dead algae decay creates massive BOD, crashing DO levels.
* *Game Algorithm:* Treat algae as an environmental hazard or "hard mode." When an algae bloom is triggered, increase the global base decay rate by $300\%$, forcing the player to use higher fountain throughput to prevent anoxia.

### Phase 4: Fountain Mechanics

Implement the hardware that counteracts the natural DO decay.

* **Placement:** Allow the player to click to spawn the pump (snaps to the lowest unblocked voxel) and the sprayer (snaps to the highest unblocked voxel).
* **Transfer Logic:** Each tick, remove a calculated DO value from the pump voxel. Add that DO, plus an "aeration bonus" (representing the spray through the air), to the sprayer voxel.
* **Convection Current:** Implement an algorithm that shifts water values toward the pump voxel. If the pump removes water from `[x, y, z]`, the water from `[x, y, z+1]` shifts down to replace it, pulling highly oxygenated surface water downward.

### Phase 5: Rendering and Shaders

Visualize the 3D grid efficiently in Godot.

* **MultiMeshInstance3D:** Use this node to render the thousands of water voxels in a single draw call. Update the `color` attribute of each instance per tick based on its `DO_Level` (red = $0$ mg/L, cyan = $8+$ mg/L).
* **Slice View Shader:** Write a custom Spatial Shader for the water material. Pass a uniform variable (e.g., `clip_plane_x`) linked to the UI slider. The shader must discard the fragment if its `VERTEX.x` is greater than `clip_plane_x`, creating the clean cross-section.

### Phase 6: UI and Progression

Construct the interactive HUD.

* **Controls:** Build standard Godot UI (`Control` nodes) for Season, Rain, Wind, Algae triggers, and the fountain's Liters Per Minute (LPM) slider.
* **Scoring System:** Calculate $Efficiency = (Average Grid DO) / (Fountain Energy Consumed)$. Display this dynamically to guide player optimization.