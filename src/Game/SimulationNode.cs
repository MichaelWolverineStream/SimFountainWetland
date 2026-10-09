using System;
using Godot;
using SimCore;
using GArray = Godot.Collections.Array;
using GDict = Godot.Collections.Dictionary;

namespace SimFountainWetland.Game;

// Owns the voxel grid, DO model and daily statistics. GDScript drives it through the PascalCase API below.
// Positions are in Level-local space; columns use GridMap (x, z) coordinates.
public partial class SimulationNode : Node
{
    [Signal] public delegate void TicksAdvancedEventHandler();
    [Signal] public delegate void DayCompletedEventHandler(GDict summary);
    [Signal] public delegate void FastForwardProgressEventHandler(int done, int total);
    [Signal] public delegate void FastForwardFinishedEventHandler();

    [Export] public Node3D? Level { get; set; }
    [Export] public WaterVoxelRenderer? Renderer { get; set; }
    [Export] public SimParamsResource? Params { get; set; }
    [Export] public double TickIntervalSeconds { get; set; } = 0.5;
    [Export] public int FastForwardTicksPerFrame { get; set; } = 24;

    VoxelGrid? _grid;
    DOModel? _model;
    DailyStats? _daily;
    Vector3I _origin;
    int _ticksPerTimeout = 1;
    int _fastForwardDone;
    int _fastForwardTotal;
    double _todayKwh;
    double _totalKwh;

    public bool IsLoaded => _model != null;
    public string LoadError { get; private set; } = "";
    public int TicksPerTimeout => _ticksPerTimeout;
    public bool IsFastForwarding => _fastForwardTotal > 0;
    public int WaterCellCount => _grid?.WaterCount ?? 0;
    public float HypoxiaThreshold => _model?.Config.HypoxiaThreshold ?? 0f;
    public float MaxLpm => _model?.Config.MaxLpm ?? 0f;

    public override void _Ready()
    {
        GD.Print($"SimCore loaded on .NET {Info.RuntimeVersion}");
        var timer = new Timer { WaitTime = TickIntervalSeconds, Autostart = true };
        timer.Timeout += OnTimeout;
        AddChild(timer);
        Load();
    }

    public override void _Process(double delta)
    {
        if (!IsFastForwarding) return;
        // Handlers of DayCompleted may stop the fast-forward mid-batch.
        int end = Math.Min(_fastForwardDone + FastForwardTicksPerFrame, _fastForwardTotal);
        while (IsFastForwarding && _fastForwardDone < end)
        {
            StepOnce();
            _fastForwardDone++;
        }
        Publish();
        if (!IsFastForwarding) return;
        EmitSignal(SignalName.FastForwardProgress, _fastForwardDone, _fastForwardTotal);
        if (_fastForwardDone < _fastForwardTotal) return;
        StopFastForward();
        EmitSignal(SignalName.FastForwardFinished);
    }

    void Load()
    {
        var gridMap = Level?.GetNodeOrNull<GridMap>("GridMap");
        if (Level == null || gridMap == null)
        {
            Fail("Simulation needs a Level with a GridMap child.");
            return;
        }

        int waterLevelY = Level.Get("water_level_y").AsInt32();
        var seed = Level.Call("get_seed_cell").AsVector3I();
        var config = Params?.ToConfig() ?? new SimConfig();
        try
        {
            _grid = GridMapVoxelizer.Voxelize(gridMap, seed, waterLevelY, config.CellSizeY, out _origin);
            _model = new DOModel(_grid, config);
            _daily = new DailyStats(config, _grid.LayerCount);
        }
        catch (BasinLeakException e)
        {
            Fail($"Basin is not watertight: water escapes the level next to cell {ToMap(e.Cell)}.");
            return;
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException)
        {
            Fail(e.Message);
            return;
        }

        Renderer?.Build(_grid, _origin);
        Renderer?.UpdateValues(_model.Do);
        GD.Print($"Water cells: {_grid.WaterCount}, layers: {_grid.LayerCount}");
    }

    void Fail(string message)
    {
        LoadError = message;
        GD.PushError(message);
    }

    void OnTimeout()
    {
        if (!IsLoaded || IsFastForwarding || _ticksPerTimeout <= 0) return;
        Advance(_ticksPerTimeout);
    }

    void Advance(int ticks)
    {
        if (ticks <= 0) return;
        for (int i = 0; i < ticks; i++) StepOnce();
        Publish();
    }

    void StepOnce()
    {
        if (_model == null || _daily == null) return;
        _model.Step();
        var stats = _model.Stats;
        _todayKwh += stats.EnergyKwh;
        _totalKwh += stats.EnergyKwh;
        if (stats.Hour == 23) _todayKwh = 0;
        if (_daily.Add(stats, _model.LayerMeans) is { } day)
            EmitSignal(SignalName.DayCompleted, ToDict(day));
    }

    void Publish()
    {
        if (_model == null) return;
        Renderer?.UpdateValues(_model.Do);
        EmitSignal(SignalName.TicksAdvanced);
    }

    // ---- Time control ----

    public void SetSpeed(int ticksPerTimeout) => _ticksPerTimeout = Math.Max(0, ticksPerTimeout);

    public void StepTicks(int count) => Advance(count);

    public void StartFastForward(int ticks)
    {
        _fastForwardDone = 0;
        _fastForwardTotal = Math.Max(0, ticks);
    }

    public void StopFastForward()
    {
        _fastForwardDone = 0;
        _fastForwardTotal = 0;
    }

    public void ResetSimulation()
    {
        if (_model == null || _daily == null) return;
        StopFastForward();
        _model.Reset();
        _daily.Reset();
        _todayKwh = 0;
        _totalKwh = 0;
        Publish();
    }

    public void ResetDailyStats() => _daily?.Reset();

    public bool IsSteady(float tolerance) => _daily?.IsSteady(tolerance) ?? false;

    public GDict GetLastDay() => _daily?.LastDay is { } day ? ToDict(day) : new GDict();

    // ---- Environment ----

    public void SetEnvironment(int season, int wind, bool rain, bool bloom)
    {
        if (_model == null) return;
        var env = _model.Environment;
        env.Season = (Season)Math.Clamp(season, 0, 3);
        env.Wind = (Wind)Math.Clamp(wind, 0, 2);
        env.Rain = rain;
        env.AlgaeBloom = bloom;
    }

    // ---- Fountains ----

    public bool IsWaterColumn(int x, int z) => _grid != null && _grid.ColumnTop(x - _origin.X, z - _origin.Z) >= 0;

    public Vector3 GetColumnTopCenter(int x, int z) => CellCenter(_grid?.ColumnTop(x - _origin.X, z - _origin.Z) ?? -1);

    public Vector3 GetColumnBottomCenter(int x, int z) => CellCenter(_grid?.ColumnBottom(x - _origin.X, z - _origin.Z) ?? -1);

    public int AddFountain() => _model?.Fountains.Add().Id ?? -1;

    public bool RemoveFountain(int id) => _model?.Fountains.Remove(id) ?? false;

    public void ClearFountains() => _model?.Fountains.Clear();

    public bool PlaceFountainPump(int id, int x, int z) =>
        _model?.Fountains.Get(id)?.PlacePump(x - _origin.X, z - _origin.Z) ?? false;

    public bool PlaceFountainSprayer(int id, int x, int z) =>
        _model?.Fountains.Get(id)?.PlaceSprayer(x - _origin.X, z - _origin.Z) ?? false;

    public void SetFountainLpm(int id, float lpm) => _model?.Fountains.Get(id)?.SetLpm(lpm);

    public GArray GetFountains()
    {
        var list = new GArray();
        if (_model == null) return list;
        foreach (var f in _model.Fountains.Units)
        {
            list.Add(new GDict
            {
                ["id"] = f.Id,
                ["has_pump"] = f.PumpCell >= 0,
                ["has_sprayer"] = f.SprayerCell >= 0,
                ["active"] = f.IsActive,
                ["pump_position"] = CellCenter(f.PumpCell),
                ["sprayer_position"] = CellCenter(f.SprayerCell),
                ["pump_column"] = ColumnOf(f.PumpCell),
                ["sprayer_column"] = ColumnOf(f.SprayerCell),
                ["lpm"] = f.Lpm,
                ["head_m"] = f.HeadM,
                ["power_kw"] = f.PowerKw,
                ["pipe_length_m"] = f.PipeLengthM,
                ["pump_zone_radius"] = f.PumpZoneRadius,
                ["spray_radius"] = f.SprayRadius,
            });
        }
        return list;
    }

    public GDict GetFountainTotals()
    {
        int count = 0, active = 0;
        float lpm = 0f, power = 0f;
        if (_model != null)
        {
            foreach (var f in _model.Fountains.Units)
            {
                count++;
                if (!f.IsActive) continue;
                active++;
                lpm += f.Lpm;
                power += f.PowerKw;
            }
        }
        return new GDict { ["count"] = count, ["active"] = active, ["total_lpm"] = lpm, ["power_kw"] = power };
    }

    // ---- Stats ----

    public GDict GetStats()
    {
        var d = new GDict();
        if (_model == null || _daily == null) return d;
        var s = _model.Stats;
        d["tick"] = s.Tick;
        d["day"] = s.Day;
        d["hour"] = s.Hour;
        d["mean_do"] = s.MeanDo;
        d["min_do"] = s.MinDo;
        d["max_do"] = s.MaxDo;
        d["surface_mean_do"] = s.SurfaceMeanDo;
        d["bottom_mean_do"] = s.BottomMeanDo;
        d["total_do_kg"] = s.TotalDoKg;
        d["hypoxic_fraction"] = s.HypoxicFraction;
        d["power_kw"] = s.PowerKw;
        d["today_kwh"] = _todayKwh;
        d["total_kwh"] = _totalKwh;
        d["rolling_mean_do"] = _daily.RollingMeanDo;
        d["rolling_hypoxic_fraction"] = _daily.RollingHypoxicFraction;
        d["water_cells"] = _grid?.WaterCount ?? 0;
        return d;
    }

    public float[] GetLayerMeans() => _model == null ? [] : (float[])_model.LayerMeans.Clone();

    // ---- Geometry ----

    public Vector3I GetGridOrigin() => _origin;

    public Vector3I GetGridSize() => _grid == null ? Vector3I.Zero : new Vector3I(_grid.SizeX, _grid.SizeY, _grid.SizeZ);

    // Top face of the surface water layer.
    public float GetWaterSurfaceY() => _grid == null ? 0f : _origin.Y + _grid.WaterLevelY + 1f;

    Vector3 CellCenter(int waterIndex)
    {
        if (_grid == null || waterIndex < 0) return Vector3.Zero;
        var p = ToMap(_grid.WaterCoords(waterIndex));
        return new Vector3(p.X + 0.5f, p.Y + 0.5f, p.Z + 0.5f);
    }

    Vector3I ToMap(Int3 p) => new(p.X + _origin.X, p.Y + _origin.Y, p.Z + _origin.Z);

    Vector2I ColumnOf(int waterIndex)
    {
        if (_grid == null || waterIndex < 0) return new Vector2I(-1, -1);
        var p = ToMap(_grid.WaterCoords(waterIndex));
        return new Vector2I(p.X, p.Z);
    }

    static GDict ToDict(DaySummary day) => new()
    {
        ["day"] = day.Day,
        ["mean_do"] = day.MeanDo,
        ["min_do"] = day.MinDo,
        ["max_do"] = day.MaxDo,
        ["surface_mean_do"] = day.SurfaceMeanDo,
        ["bottom_mean_do"] = day.BottomMeanDo,
        ["hypoxic_fraction"] = day.HypoxicFraction,
        ["total_do_kg"] = day.TotalDoKg,
        ["energy_kwh"] = day.EnergyKwh,
        ["layer_mean"] = day.LayerMean,
        ["layer_min"] = day.LayerMin,
        ["layer_max"] = day.LayerMax,
    };
}
