using SimCore;

namespace SimCore.Tests;

public class DOModelTests
{
    [Fact]
    public void DiffusionConservesTotalDo()
    {
        var model = new DOModel(TestGrids.Box(12, 10, 8), TestGrids.NoSources());
        model.Environment.Rain = true;
        for (int i = 0; i < model.Do.Length; i++) model.Do[i] = i % 7 * 2f;
        double before = TestGrids.Total(model.Do);

        for (int t = 0; t < 200; t++) model.Step();

        Assert.Equal(before, TestGrids.Total(model.Do), before * 1e-4);
    }

    [Fact]
    public void DiffusionDoesNotLeakThroughSolids()
    {
        var model = new DOModel(TestGrids.Box(6, 6, 3), TestGrids.NoSources());
        Array.Fill(model.Do, 5f);

        for (int t = 0; t < 50; t++) model.Step();

        Assert.All(model.Do, v => Assert.Equal(5f, v, 1e-4f));
    }

    [Fact]
    public void ReaerationConvergesToSaturation()
    {
        var config = TestGrids.NoSources();
        config.SurfaceReaeration = 0.2f;
        config.DiffusionV = 0.2f;
        var model = new DOModel(TestGrids.Box(6, 6, 3), config);
        model.Environment.Season = Season.Winter;
        Array.Fill(model.Do, 0f);

        TestGrids.RunDays(model, 20);

        Assert.All(model.Do, v => Assert.Equal(config.Winter.DoSat, v, 0.05f));
    }

    [Fact]
    public void SupersaturatedSurfaceDegasses()
    {
        var config = TestGrids.NoSources();
        config.SurfaceReaeration = 0.2f;
        var model = new DOModel(TestGrids.Box(6, 6, 3), config);
        model.Environment.Season = Season.Summer;
        Array.Fill(model.Do, 15f);

        TestGrids.RunDays(model, 1);

        Assert.True(model.Stats.SurfaceMeanDo < 15f);
        Assert.True(model.Stats.SurfaceMeanDo > config.Summer.DoSat);
    }

    [Fact]
    public void SedimentDemandNeverGoesNegative()
    {
        var config = new SimConfig { Sod = 3f, Bod = 0.5f };
        var model = new DOModel(TestGrids.Box(8, 8, 4), config);
        model.Environment.Season = Season.Summer;
        model.Environment.Wind = Wind.Calm;
        Array.Fill(model.Do, 0.5f);

        for (int t = 0; t < 48; t++)
        {
            model.Step();
            Assert.True(model.Stats.MinDo >= 0f);
        }
    }

    [Fact]
    public void SummerCalmStratifies()
    {
        var model = new DOModel(TestGrids.Box(16, 16, 10), new SimConfig());
        model.Environment.Season = Season.Summer;
        model.Environment.Wind = Wind.Calm;
        model.Reset();

        TestGrids.RunDays(model, 7);

        Assert.True(model.Stats.SurfaceMeanDo >= model.Stats.BottomMeanDo + 2f,
            $"surface {model.Stats.SurfaceMeanDo}, bottom {model.Stats.BottomMeanDo}");
    }

    [Fact]
    public void BloomCausesDiurnalSwing()
    {
        var model = new DOModel(TestGrids.Box(12, 12, 8), new SimConfig());
        model.Environment.Season = Season.Summer;
        model.Environment.Wind = Wind.Calm;
        model.Environment.AlgaeBloom = true;
        model.Reset();
        TestGrids.RunDays(model, 1);

        float at05 = 0f, at15 = 0f;
        for (int t = 0; t < 24; t++)
        {
            int hour = model.Environment.Hour;
            model.Step();
            if (hour == 5) at05 = model.Stats.SurfaceMeanDo;
            if (hour == 15) at15 = model.Stats.SurfaceMeanDo;
        }

        Assert.True(at15 > at05, $"15:00 {at15}, 05:00 {at05}");
    }

    [Fact]
    public void FountainRaisesBottomDo()
    {
        static DOModel Create()
        {
            var m = new DOModel(TestGrids.Box(16, 16, 10), new SimConfig());
            m.Environment.Season = Season.Summer;
            m.Environment.Wind = Wind.Calm;
            m.Reset();
            return m;
        }

        var baseline = Create();
        var withFountain = Create();
        Assert.True(withFountain.Fountain.PlacePump(8, 8));
        Assert.True(withFountain.Fountain.PlaceSprayer(8, 8));
        withFountain.Fountain.SetLpm(1000f);

        TestGrids.RunDays(baseline, 3);
        TestGrids.RunDays(withFountain, 3);

        Assert.True(withFountain.Stats.BottomMeanDo > baseline.Stats.BottomMeanDo,
            $"fountain {withFountain.Stats.BottomMeanDo}, baseline {baseline.Stats.BottomMeanDo}");
        Assert.True(withFountain.Stats.EnergyKwh > 0f);
    }

    [Fact]
    public void SimulationIsDeterministic()
    {
        static float[] Run()
        {
            var m = new DOModel(TestGrids.Box(12, 10, 6), new SimConfig());
            m.Environment.Season = Season.Summer;
            m.Environment.AlgaeBloom = true;
            m.Fountain.PlacePump(5, 5);
            m.Fountain.PlaceSprayer(3, 4);
            m.Fountain.SetLpm(800f);
            for (int t = 0; t < 100; t++) m.Step();
            return m.Do;
        }

        Assert.Equal(Run(), Run());
    }

    [Fact]
    public void StepIsFastEnoughForLargeBasins()
    {
        var model = new DOModel(TestGrids.Box(60, 60, 16), new SimConfig());
        Assert.True(model.Grid.WaterCount > 50_000);
        model.Fountain.PlacePump(30, 30);
        model.Fountain.PlaceSprayer(30, 30);
        model.Fountain.SetLpm(2000f);

        var watch = System.Diagnostics.Stopwatch.StartNew();
        for (int t = 0; t < 100; t++) model.Step();
        watch.Stop();

        Assert.True(watch.ElapsedMilliseconds < 5000, $"100 ticks took {watch.ElapsedMilliseconds} ms");
    }

    [Fact]
    public void InvalidDiffusionIsRejected()
    {
        var config = new SimConfig { DiffusionH = 0.2f, DiffusionV = 0.2f };
        Assert.Throws<InvalidOperationException>(() => new DOModel(TestGrids.Box(6, 6, 3), config));
    }
}
