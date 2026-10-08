using SimCore;

namespace SimCore.Tests;

public class VoxelGridTests
{
    [Fact]
    public void GridIndexRoundTrips()
    {
        var grid = TestGrids.Box(10, 8, 6);
        for (int y = 0; y < grid.SizeY; y++)
        for (int z = 0; z < grid.SizeZ; z++)
        for (int x = 0; x < grid.SizeX; x++)
            Assert.Equal(new Int3(x, y, z), grid.GridCoords(grid.GridIndex(x, y, z)));
    }

    [Fact]
    public void FloodFillCountsBowlInterior()
    {
        var grid = TestGrids.Box(10, 8, 6);
        Assert.Equal(8 * 6 * 6, grid.WaterCount);
        Assert.Equal(6, grid.LayerCount);
    }

    [Fact]
    public void FloodFillDetectsLeak()
    {
        Assert.Throws<BasinLeakException>(() => TestGrids.Box(10, 8, 6, hole: new Int3(9, 3, 4)));
    }

    [Fact]
    public void ColumnsAndBoundaryNeighbors()
    {
        var grid = TestGrids.Box(10, 8, 6);
        int top = grid.ColumnTop(1, 1);
        int bottom = grid.ColumnBottom(1, 1);

        Assert.Equal(new Int3(1, 6, 1), grid.WaterCoords(top));
        Assert.Equal(new Int3(1, 1, 1), grid.WaterCoords(bottom));
        Assert.True(grid.IsSurface(top));
        Assert.True(grid.IsBottom(bottom));
        Assert.Equal(6, grid.GetColumn(1, 1).Length);
        Assert.Equal(2, grid.SideBedFaces[bottom]);
        Assert.Equal(bottom, grid.Neighbors[bottom * 6 + VoxelGrid.NegX]);
        Assert.Equal(-1, grid.ColumnTop(0, 0));
    }
}
