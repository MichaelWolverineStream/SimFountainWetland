using SimCore;

namespace SimCore.Tests;

public class FountainAndEnergyTests
{
    [Fact]
    public void PowerMatchesHydraulicFormula()
    {
        Assert.Equal(1.635f, EnergyModel.PowerKw(1000f, 5f, 0.5f), 0.01f);
    }

    [Fact]
    public void FrictionScalesWithFlowSquared()
    {
        float at1000 = EnergyModel.FrictionHeadM(20f, 1000f, 0.04f, 1000f);
        float at2000 = EnergyModel.FrictionHeadM(20f, 2000f, 0.04f, 1000f);
        Assert.Equal(0.8f, at1000, 1e-4f);
        Assert.Equal(4f * at1000, at2000, 1e-4f);
    }

    [Fact]
    public void PlacementSnapsToBottomAndTop()
    {
        var grid = TestGrids.Box(10, 10, 6);
        var fountain = new FountainModel(grid, new SimConfig());

        Assert.True(fountain.PlacePump(4, 4));
        Assert.True(fountain.PlaceSprayer(6, 4));
        Assert.False(fountain.PlacePump(0, 0));

        Assert.Equal(new Int3(4, 1, 4), grid.WaterCoords(fountain.PumpCell));
        Assert.Equal(new Int3(6, 6, 4), grid.WaterCoords(fountain.SprayerCell));
    }

    [Fact]
    public void HeadIncludesSprayHeightAndPipeFriction()
    {
        var config = new SimConfig();
        var grid = TestGrids.Box(10, 10, 6);
        var fountain = new FountainModel(grid, config);
        fountain.PlacePump(4, 4);
        fountain.PlaceSprayer(7, 8);
        fountain.SetLpm(1000f);

        float expectedPipe = grid.DepthM[fountain.PumpCell] + 5f * config.CellSizeXZ;
        Assert.Equal(expectedPipe, fountain.PipeLengthM, 1e-4f);
        Assert.Equal(config.SprayHeightM + config.PipeFrictionPerMeter * expectedPipe, fountain.HeadM, 1e-4f);
        Assert.True(fountain.PowerKw > 0f);
    }

    [Fact]
    public void InactiveFountainUsesNoPower()
    {
        var fountain = new FountainModel(TestGrids.Box(10, 10, 6), new SimConfig());
        fountain.PlacePump(4, 4);
        fountain.SetLpm(1000f);
        Assert.False(fountain.IsActive);
        Assert.Equal(0f, fountain.PowerKw);
    }

    [Fact]
    public void LpmMapsToVoxelsPerTick()
    {
        var fountain = new FountainModel(TestGrids.Box(10, 10, 6), new SimConfig());
        fountain.SetLpm(1000f);
        Assert.Equal(60f, fountain.VoxelsPerTick, 1e-3f);
    }
}
