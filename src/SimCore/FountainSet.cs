namespace SimCore;

// All pump + sprayer units in the basin; active units are applied in insertion order each tick.
public sealed class FountainSet
{
    readonly VoxelGrid _grid;
    readonly SimConfig _config;
    readonly List<FountainModel> _units = [];
    int _nextId = 1;

    public FountainSet(VoxelGrid grid, SimConfig config)
    {
        _grid = grid;
        _config = config;
    }

    public IReadOnlyList<FountainModel> Units => _units;
    public int Count => _units.Count;
    public int Version { get; private set; }

    public bool AnyActive
    {
        get
        {
            foreach (var unit in _units)
                if (unit.IsActive) return true;
            return false;
        }
    }

    public float PowerKw
    {
        get
        {
            float total = 0f;
            foreach (var unit in _units) total += unit.PowerKw;
            return total;
        }
    }

    public FountainModel Add()
    {
        var unit = new FountainModel(_grid, _config, _nextId++);
        unit.Changed = () => Version++;
        _units.Add(unit);
        Version++;
        return unit;
    }

    public FountainModel? Get(int id)
    {
        foreach (var unit in _units)
            if (unit.Id == id) return unit;
        return null;
    }

    public bool Remove(int id)
    {
        var unit = Get(id);
        if (unit is null) return false;
        unit.Changed = null;
        _units.Remove(unit);
        Version++;
        return true;
    }

    public void Clear()
    {
        foreach (var unit in _units) unit.Changed = null;
        _units.Clear();
        Version++;
    }

    internal void Apply(float[] values, float doSat)
    {
        foreach (var unit in _units) unit.Apply(values, doSat);
    }
}
