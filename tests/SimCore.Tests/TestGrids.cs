using SimCore;

namespace SimCore.Tests;

static class TestGrids
{
    // Rectangular basin: solid floor at y=0 and walls on the outer ring; water fills y=1..depth.
    public static VoxelGrid Box(int sizeX, int sizeZ, int depth, float cellHeightM = 0.25f, Int3? hole = null)
    {
        int sizeY = depth + 2;
        var solid = new bool[sizeX * sizeY * sizeZ];
        for (int y = 0; y < sizeY; y++)
        for (int z = 0; z < sizeZ; z++)
        for (int x = 0; x < sizeX; x++)
        {
            bool wall = y == 0 || x == 0 || z == 0 || x == sizeX - 1 || z == sizeZ - 1;
            solid[x + sizeX * (z + sizeZ * y)] = wall;
        }
        if (hole is { } h) solid[h.X + sizeX * (h.Z + sizeZ * h.Y)] = false;
        return VoxelGrid.FromSolidMask(solid, sizeX, sizeY, sizeZ, new Int3(sizeX / 2, 1, sizeZ / 2), depth, cellHeightM);
    }

    public static SimConfig NoSources() => new()
    {
        Bod = 0f,
        Sod = 0f,
        PhotosynthesisMax = 0f,
        SurfaceReaeration = 0f,
        RainRelaxation = 0f,
    };

    public static void RunDays(DOModel model, int days)
    {
        for (int t = 0; t < days * 24; t++) model.Step();
    }

    public static double Total(float[] values)
    {
        double sum = 0;
        foreach (float v in values) sum += v;
        return sum;
    }
}
