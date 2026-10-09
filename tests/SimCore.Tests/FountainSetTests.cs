using SimCore;

namespace SimCore.Tests;

public class FountainSetTests
{
    static FountainModel AddUnit(FountainSet set, int x, int z, float lpm)
    {
        var unit = set.Add();
        Assert.True(unit.PlacePump(x, z));
        Assert.True(unit.PlaceSprayer(x, z));
        unit.SetLpm(lpm);
        return unit;
    }

    static DOModel SummerCalm()
    {
        var model = new DOModel(TestGrids.Box(32, 16, 10), new SimConfig());
        model.Environment.Season = Season.Summer;
        model.Environment.Wind = Wind.Calm;
        model.Reset();
        return model;
    }

    [Fact]
    public void IdsAreUniqueAndNeverReused()
    {
        var set = new FountainSet(TestGrids.Box(10, 10, 6), new SimConfig());
        var a = set.Add();
        var b = set.Add();
        Assert.NotEqual(a.Id, b.Id);

        Assert.True(set.Remove(a.Id));
        var c = set.Add();
        Assert.NotEqual(a.Id, c.Id);
        Assert.NotEqual(b.Id, c.Id);
        Assert.Same(c, set.Get(c.Id));
        Assert.Null(set.Get(a.Id));
    }

    [Fact]
    public void RemoveAndClear()
    {
        var set = new FountainSet(TestGrids.Box(10, 10, 6), new SimConfig());
        var a = set.Add();
        set.Add();

        Assert.True(set.Remove(a.Id));
        Assert.False(set.Remove(a.Id));
        Assert.Equal(1, set.Count);

        set.Clear();
        Assert.Equal(0, set.Count);
        Assert.False(set.AnyActive);
    }

    [Fact]
    public void PowerIsTheSumOfActiveUnits()
    {
        var set = new FountainSet(TestGrids.Box(16, 10, 6), new SimConfig());
        var a = AddUnit(set, 4, 4, 1000f);
        var b = AddUnit(set, 11, 5, 1500f);
        set.Add().PlacePump(8, 8);

        Assert.True(set.AnyActive);
        Assert.Equal(a.PowerKw + b.PowerKw, set.PowerKw, 1e-4f);
    }

    [Fact]
    public void VersionTracksEdits()
    {
        var set = new FountainSet(TestGrids.Box(10, 10, 6), new SimConfig());
        int v0 = set.Version;
        var unit = set.Add();
        int v1 = set.Version;
        unit.SetLpm(500f);
        int v2 = set.Version;
        set.Remove(unit.Id);
        int v3 = set.Version;
        unit.SetLpm(900f);

        Assert.True(v0 < v1 && v1 < v2 && v2 < v3);
        Assert.Equal(v3, set.Version);
    }

    [Fact]
    public void TwoUnitsAerateMoreThanOne()
    {
        var one = SummerCalm();
        var two = SummerCalm();
        AddUnit(one.Fountains, 8, 8, 500f);
        AddUnit(two.Fountains, 8, 8, 500f);
        AddUnit(two.Fountains, 23, 8, 500f);

        TestGrids.RunDays(one, 3);
        TestGrids.RunDays(two, 3);

        Assert.True(two.Stats.BottomMeanDo > one.Stats.BottomMeanDo,
            $"two {two.Stats.BottomMeanDo}, one {one.Stats.BottomMeanDo}");
        Assert.True(two.Stats.PowerKw > one.Stats.PowerKw);
    }

    [Fact]
    public void RemovedUnitStopsAffectingTheModel()
    {
        var none = SummerCalm();
        var removed = SummerCalm();
        var unit = AddUnit(removed.Fountains, 8, 8, 1000f);
        removed.Step();
        removed.Fountains.Remove(unit.Id);
        removed.Reset();
        none.Step();
        none.Reset();

        TestGrids.RunDays(none, 1);
        TestGrids.RunDays(removed, 1);

        Assert.Equal(none.Do, removed.Do);
    }
}
