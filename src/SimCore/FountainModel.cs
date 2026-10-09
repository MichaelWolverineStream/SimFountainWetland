namespace SimCore;

// Pump draws from the bottom of a zone around its column (pulling that zone's water column down);
// the sprayer aerates the drawn water and mixes it into a surface footprint. Water mass is abstracted.
public sealed class FountainModel
{
    readonly VoxelGrid _grid;
    readonly SimConfig _config;
    readonly List<int[]> _pumpZone = [];
    readonly List<int> _sprayFootprint = [];

    public FountainModel(VoxelGrid grid, SimConfig config, int id = 0)
    {
        _grid = grid;
        _config = config;
        Id = id;
    }

    public int Id { get; }
    public int PumpCell { get; private set; } = -1;
    public int SprayerCell { get; private set; } = -1;
    public float Lpm { get; private set; }
    public int ZoneVersion { get; private set; }

    public bool IsActive => PumpCell >= 0 && SprayerCell >= 0 && Lpm > 0f;

    public IReadOnlyList<int[]> PumpZoneColumns => _pumpZone;
    public IReadOnlyList<int> SprayFootprint => _sprayFootprint;

    internal Action? Changed;

    public float PumpZoneRadius => 1f + Lpm / _config.PumpZoneLpmPerRadius;
    public float SprayRadius => 1f + Lpm / _config.SprayLpmPerRadius;

    public float VoxelsPerTick => Lpm * 60f * _config.TickHours / 1000f / _config.CellVolumeM3;

    public float PipeLengthM
    {
        get
        {
            if (PumpCell < 0 || SprayerCell < 0) return 0f;
            var p = _grid.WaterCoords(PumpCell);
            var s = _grid.WaterCoords(SprayerCell);
            float horizontal = MathF.Sqrt((p.X - s.X) * (p.X - s.X) + (p.Z - s.Z) * (p.Z - s.Z)) * _config.CellSizeXZ;
            return _grid.DepthM[PumpCell] + horizontal;
        }
    }

    public float HeadM => _config.SprayHeightM
        + EnergyModel.FrictionHeadM(PipeLengthM, Lpm, _config.PipeFrictionPerMeter, _config.PipeReferenceLpm);

    public float PowerKw => IsActive ? EnergyModel.PowerKw(Lpm, HeadM, _config.PumpEfficiency) : 0f;

    public bool PlacePump(int x, int z)
    {
        int cell = _grid.ColumnBottom(x, z);
        if (cell < 0) return false;
        PumpCell = cell;
        RebuildZones();
        return true;
    }

    public bool PlaceSprayer(int x, int z)
    {
        int cell = _grid.ColumnTop(x, z);
        if (cell < 0) return false;
        SprayerCell = cell;
        RebuildZones();
        return true;
    }

    public void SetLpm(float lpm)
    {
        Lpm = Math.Clamp(lpm, 0f, _config.MaxLpm);
        RebuildZones();
    }

    public void Clear()
    {
        PumpCell = -1;
        SprayerCell = -1;
        RebuildZones();
    }

    internal void Apply(float[] values, float doSat)
    {
        if (!IsActive || _pumpZone.Count == 0 || _sprayFootprint.Count == 0) return;

        float volume = VoxelsPerTick;

        float doIn = 0f;
        foreach (var column in _pumpZone) doIn += values[column[^1]];
        doIn /= _pumpZone.Count;

        float shift = volume / _pumpZone.Count;
        int substeps = Math.Clamp((int)MathF.Ceiling(shift), 1, _config.MaxAdvectionSubsteps);
        float fraction = MathF.Min(1f, shift / substeps);
        for (int s = 0; s < substeps; s++)
        {
            foreach (var column in _pumpZone)
            {
                // Bottom-up so each cell blends with the not-yet-updated cell above it.
                for (int j = column.Length - 1; j > 0; j--)
                    values[column[j]] += fraction * (values[column[j - 1]] - values[column[j]]);
            }
        }

        float doOut = doIn + _config.SprayEfficiency * (doSat - doIn);
        float mix = MathF.Min(1f, volume / _sprayFootprint.Count);
        foreach (int cell in _sprayFootprint)
            values[cell] += mix * (doOut - values[cell]);
    }

    void RebuildZones()
    {
        _pumpZone.Clear();
        _sprayFootprint.Clear();
        ZoneVersion++;

        if (PumpCell >= 0)
        {
            var p = _grid.WaterCoords(PumpCell);
            foreach (var (x, z) in ColumnsWithin(p.X, p.Z, PumpZoneRadius))
            {
                var column = _grid.GetColumn(x, z);
                if (column.Length > 0) _pumpZone.Add(column);
            }
        }

        if (SprayerCell >= 0)
        {
            var s = _grid.WaterCoords(SprayerCell);
            foreach (var (x, z) in ColumnsWithin(s.X, s.Z, SprayRadius))
            {
                int top = _grid.ColumnTop(x, z);
                if (top >= 0) _sprayFootprint.Add(top);
            }
        }
        Changed?.Invoke();
    }

    IEnumerable<(int X, int Z)> ColumnsWithin(int cx, int cz, float radius)
    {
        int r = (int)MathF.Floor(radius);
        float r2 = radius * radius;
        for (int z = cz - r; z <= cz + r; z++)
        for (int x = cx - r; x <= cx + r; x++)
        {
            int dx = x - cx, dz = z - cz;
            if (dx * dx + dz * dz <= r2) yield return (x, z);
        }
    }
}
