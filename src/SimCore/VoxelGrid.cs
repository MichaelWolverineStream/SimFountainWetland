namespace SimCore;

public sealed class BasinLeakException(Int3 cell)
    : Exception($"Water flood fill escaped the grid next to cell {cell}; the basin is not watertight.")
{
    public Int3 Cell { get; } = cell;
}

// Y-up voxel grid. Grid index = x + SizeX * (z + SizeZ * y). Water cells are stored compactly.
public sealed class VoxelGrid
{
    public const int NegX = 0, PosX = 1, NegZ = 2, PosZ = 3, Down = 4, Up = 5;

    static readonly (int X, int Y, int Z)[] Directions =
        [(-1, 0, 0), (1, 0, 0), (0, 0, -1), (0, 0, 1), (0, -1, 0), (0, 1, 0)];

    readonly int[] _gridToWater;
    readonly int[] _columnTop;
    readonly int[] _columnBottom;
    readonly int[] _columnCells;

    VoxelGrid(int sizeX, int sizeY, int sizeZ, int waterLevelY, float cellHeightM, bool[] isWater)
    {
        SizeX = sizeX;
        SizeY = sizeY;
        SizeZ = sizeZ;
        WaterLevelY = waterLevelY;

        _gridToWater = new int[isWater.Length];
        var waterToGrid = new List<int>();
        for (int g = 0; g < isWater.Length; g++)
        {
            _gridToWater[g] = isWater[g] ? waterToGrid.Count : -1;
            if (isWater[g]) waterToGrid.Add(g);
        }
        WaterToGrid = [.. waterToGrid];

        int n = WaterToGrid.Length;
        Neighbors = new int[n * 6];
        SideBedFaces = new byte[n];
        DepthLayer = new int[n];
        DepthM = new float[n];
        _columnCells = new int[sizeX * sizeZ];
        int minY = waterLevelY;
        for (int i = 0; i < n; i++)
        {
            var p = GridCoords(WaterToGrid[i]);
            _columnCells[p.X + sizeX * p.Z]++;
            for (int d = 0; d < 6; d++)
            {
                var (dx, dy, dz) = Directions[d];
                int w = WaterIndexAt(p.X + dx, p.Y + dy, p.Z + dz);
                // Self-reference gives a zero-flux boundary in diffusion.
                Neighbors[i * 6 + d] = w >= 0 ? w : i;
                if (w < 0 && d < Down) SideBedFaces[i]++;
            }
            DepthLayer[i] = waterLevelY - p.Y;
            DepthM[i] = (DepthLayer[i] + 0.5f) * cellHeightM;
            minY = Math.Min(minY, p.Y);
        }
        LayerCount = waterLevelY - minY + 1;

        _columnTop = new int[sizeX * sizeZ];
        _columnBottom = new int[sizeX * sizeZ];
        for (int z = 0; z < sizeZ; z++)
        for (int x = 0; x < sizeX; x++)
        {
            int top = WaterIndexAt(x, waterLevelY, z);
            int bottom = top;
            if (top >= 0)
                while (Neighbors[bottom * 6 + Down] != bottom) bottom = Neighbors[bottom * 6 + Down];
            _columnTop[x + sizeX * z] = top;
            _columnBottom[x + sizeX * z] = bottom;
        }
    }

    public int SizeX { get; }
    public int SizeY { get; }
    public int SizeZ { get; }
    public int WaterLevelY { get; }
    public int LayerCount { get; }
    public int WaterCount => WaterToGrid.Length;

    public int[] WaterToGrid { get; }
    public int[] Neighbors { get; }
    public byte[] SideBedFaces { get; }
    public int[] DepthLayer { get; }
    public float[] DepthM { get; }

    public static VoxelGrid FromSolidMask(bool[] solid, int sizeX, int sizeY, int sizeZ, Int3 seed, int waterLevelY, float cellHeightM)
    {
        if (sizeX <= 0 || sizeY <= 0 || sizeZ <= 0 || solid.Length != sizeX * sizeY * sizeZ)
            throw new ArgumentException("Solid mask length does not match grid dimensions.", nameof(solid));
        if (waterLevelY < 0 || waterLevelY >= sizeY)
            throw new ArgumentOutOfRangeException(nameof(waterLevelY));

        int Index(int x, int y, int z) => x + sizeX * (z + sizeZ * y);

        bool seedInside = seed.X >= 0 && seed.X < sizeX && seed.Y >= 0 && seed.Y <= waterLevelY && seed.Z >= 0 && seed.Z < sizeZ;
        if (!seedInside || solid[Index(seed.X, seed.Y, seed.Z)])
            throw new ArgumentException("Seed must be an empty cell inside the grid at or below the water level.", nameof(seed));

        var isWater = new bool[solid.Length];
        var queue = new Queue<Int3>();
        isWater[Index(seed.X, seed.Y, seed.Z)] = true;
        queue.Enqueue(seed);
        while (queue.Count > 0)
        {
            var p = queue.Dequeue();
            foreach (var (dx, dy, dz) in Directions)
            {
                int x = p.X + dx, y = p.Y + dy, z = p.Z + dz;
                if (y > waterLevelY) continue;
                if (x < 0 || x >= sizeX || z < 0 || z >= sizeZ || y < 0) throw new BasinLeakException(p);
                int g = Index(x, y, z);
                if (solid[g] || isWater[g]) continue;
                isWater[g] = true;
                queue.Enqueue(new Int3(x, y, z));
            }
        }
        return new VoxelGrid(sizeX, sizeY, sizeZ, waterLevelY, cellHeightM, isWater);
    }

    public int GridIndex(int x, int y, int z) => x + SizeX * (z + SizeZ * y);

    public Int3 GridCoords(int gridIndex)
    {
        int x = gridIndex % SizeX;
        int rest = gridIndex / SizeX;
        return new Int3(x, rest / SizeZ, rest % SizeZ);
    }

    public Int3 WaterCoords(int waterIndex) => GridCoords(WaterToGrid[waterIndex]);

    public bool InBounds(int x, int y, int z) =>
        x >= 0 && x < SizeX && y >= 0 && y < SizeY && z >= 0 && z < SizeZ;

    public int WaterIndexAt(int x, int y, int z) => InBounds(x, y, z) ? _gridToWater[GridIndex(x, y, z)] : -1;

    public bool IsBottom(int waterIndex) => Neighbors[waterIndex * 6 + Down] == waterIndex;

    public bool IsSurface(int waterIndex) => DepthLayer[waterIndex] == 0;

    public int ColumnTop(int x, int z) => InColumns(x, z) ? _columnTop[x + SizeX * z] : -1;

    public int ColumnBottom(int x, int z) => InColumns(x, z) ? _columnBottom[x + SizeX * z] : -1;

    // Water cells of the open-surface column at (x, z), ordered top to bottom.
    public int[] GetColumn(int x, int z)
    {
        int cell = ColumnTop(x, z);
        if (cell < 0) return [];
        var cells = new List<int> { cell };
        while (!IsBottom(cell))
        {
            cell = Neighbors[cell * 6 + Down];
            cells.Add(cell);
        }
        return [.. cells];
    }

    // Mean of per-water-cell values over each (x, z) column, indexed x + SizeX * z; NaN where there is no water.
    public void ColumnMeans(ReadOnlySpan<float> values, Span<float> means)
    {
        int columns = SizeX * SizeZ;
        if (values.Length != WaterCount || means.Length != columns)
            throw new ArgumentException("Expected one value per water cell and one mean per column.");
        means.Clear();
        for (int i = 0; i < values.Length; i++)
            means[WaterToGrid[i] % columns] += values[i];
        for (int c = 0; c < columns; c++)
            means[c] = _columnCells[c] > 0 ? means[c] / _columnCells[c] : float.NaN;
    }

    bool InColumns(int x, int z) => x >= 0 && x < SizeX && z >= 0 && z < SizeZ;
}
