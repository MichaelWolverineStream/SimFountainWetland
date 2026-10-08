using System;
using Godot;
using SimCore;
using GDict = Godot.Collections.Dictionary;

namespace SimFountainWetland.Game;

// Owns the voxel grid, DO model and scoring. GDScript drives it through the PascalCase API below.
// Positions are in Level-local space; columns use GridMap (x, z) coordinates.
public partial class SimulationNode : Node
{
    [Signal] public delegate void TicksAdvancedEventHandler();
    [Signal] public delegate void DayCompletedEventHandler(GDict result);
    [Signal] public delegate void FastForwardProgressEventHandler(int done, int total);
    [Signal] public delegate void FastForwardFinishedEventHandler();

    [Export] public Node3D? Level { get; set; }
    [Export] public WaterVoxelRenderer? Renderer { get; set; }
    [Export] public SimParamsResource? Params { get; set; }
    [Export] public double TickIntervalSeconds { get; set; } = 0.5;
    [Export] public int FastForwardTicksPerFrame { get; set; } = 24;

    VoxelGrid? _grid;
    DOModel? _model;
    Scoring? _scoring;
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
    public float TargetMeanDo => _model?.Config.TargetMeanDo ?? 0f;
    public float MaxHypoxicFraction => _model?.Config.MaxHypoxicFraction ?? 0f;
    public int RequiredPassDays => _model?.Config.RequiredPassDays ?? 0;
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
            _scoring = new Scoring(config);
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
        if (_model == null || _scoring == null) return;
        _model.Step();
        var stats = _model.Stats;
        _todayKwh += stats.EnergyKwh;
        _totalKwh += stats.EnergyKwh;
        if (stats.Hour == 23) _todayKwh = 0;
        if (_scoring.Add(stats) is { } day)
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
        if (_model == null || _scoring == null) return;
        StopFastForward();
        _model.Reset();
        _scoring.Reset();
        _todayKwh = 0;
        _totalKwh = 0;
        Publish();
    }

    public void ResetScoring() => _scoring?.Reset();

    public bool IsSteady(float tolerance) => _scoring?.IsSteady(tolerance) ?? false;

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

    // ---- Fountain ----

    public bool IsWaterColumn(int x, int z) => _grid != null && _grid.ColumnTop(x - _origin.X, z - _origin.Z) >= 0;

    public Vector3 GetColumnTopCenter(int x, int z) => CellCenter(_grid?.ColumnTop(x - _origin.X, z - _origin.Z) ?? -1);

    public Vector3 GetColumnBottomCenter(int x, int z) => CellCenter(_grid?.ColumnBottom(x - _origin.X, z - _origin.Z) ?? -1);

    public bool PlacePump(int x, int z) => _model?.Fountain.PlacePump(x - _origin.X, z - _origin.Z) ?? false;

    public bool PlaceSprayer(int x, int z) => _model?.Fountain.PlaceSprayer(x - _origin.X, z - _origin.Z) ?? false;

    public void SetLpm(float lpm) => _model?.Fountain.SetLpm(lpm);

    public void ClearFountain() => _model?.Fountain.Clear();

    public GDict GetFountainInfo()
    {
        var info = new GDict();
        if (_model == null) return info;
        var f = _model.Fountain;
        info["has_pump"] = f.PumpCell >= 0;
        info["has_sprayer"] = f.SprayerCell >= 0;
        info["active"] = f.IsActive;
        info["pump_position"] = CellCenter(f.PumpCell);
        info["sprayer_position"] = CellCenter(f.SprayerCell);
        info["lpm"] = f.Lpm;
        info["head_m"] = f.HeadM;
        info["power_kw"] = f.PowerKw;
        info["pipe_length_m"] = f.PipeLengthM;
        info["pump_zone_radius"] = f.PumpZoneRadius;
        info["spray_radius"] = f.SprayRadius;
        return info;
    }

    // ---- Stats ----

    public GDict GetStats()
    {
        var d = new GDict();
        if (_model == null || _scoring == null) return d;
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
        d["rolling_mean_do"] = _scoring.RollingMeanDo;
        d["rolling_hypoxic_fraction"] = _scoring.RollingHypoxicFraction;
        d["pass_streak_days"] = _scoring.PassStreakDays;
        d["passed"] = _scoring.Passed;
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

    static GDict ToDict(DayResult day) => new()
    {
        ["day"] = day.Day,
        ["mean_do"] = day.MeanDo,
        ["hypoxic_fraction"] = day.HypoxicFraction,
        ["energy_kwh"] = day.EnergyKwh,
        ["passed"] = day.Passed,
    };
}
