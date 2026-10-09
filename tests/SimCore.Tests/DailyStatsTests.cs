using SimCore;

namespace SimCore.Tests;

public class DailyStatsTests
{
    static SimStats Tick(float meanDo, float hypoxic, float kwh = 1f, float min = 0f, float max = 0f) =>
        new(0, 0, 0, meanDo, min, max, meanDo + 1f, meanDo - 1f, 10f, hypoxic, 0f, kwh);

    static DaySummary? AddDay(DailyStats stats, float meanDo, float hypoxic, float[]? layers = null)
    {
        DaySummary? result = null;
        for (int t = 0; t < 24; t++) result = stats.Add(Tick(meanDo, hypoxic), layers ?? [meanDo, meanDo]);
        return result;
    }

    [Fact]
    public void SummarisesOneDay()
    {
        var stats = new DailyStats(new SimConfig(), 2);
        DaySummary? day = null;
        for (int t = 0; t < 24; t++)
        {
            Assert.Null(day);
            day = stats.Add(Tick(4f + t % 2, 0.2f, 0.5f, min: t == 23 ? 0.5f : 1f, max: 8f + t * 0.1f), [6f + t % 2, 2f]);
        }

        Assert.NotNull(day);
        Assert.Equal(0, day.Day);
        Assert.Equal(4.5f, day.MeanDo, 1e-4f);
        Assert.Equal(5.5f, day.SurfaceMeanDo, 1e-4f);
        Assert.Equal(3.5f, day.BottomMeanDo, 1e-4f);
        Assert.Equal(0.2f, day.HypoxicFraction, 1e-4f);
        Assert.Equal(10f, day.TotalDoKg, 1e-4f);
        Assert.Equal(12f, day.EnergyKwh, 1e-4f);
        Assert.Equal(0.5f, day.MinDo, 1e-4f);
        Assert.Equal(10.3f, day.MaxDo, 1e-4f);
        Assert.Equal(6f, day.LayerMin[0], 1e-4f);
        Assert.Equal(7f, day.LayerMax[0], 1e-4f);
        Assert.Equal(6.5f, day.LayerMean[0], 1e-4f);
        Assert.Equal(2f, day.LayerMean[1], 1e-4f);
        Assert.Same(day, stats.LastDay);
    }

    [Fact]
    public void EachDayStartsFresh()
    {
        var stats = new DailyStats(new SimConfig(), 1);
        AddDay(stats, 8f, 0f, [8f]);
        var second = AddDay(stats, 3f, 0.5f, [3f]);

        Assert.NotNull(second);
        Assert.Equal(1, second.Day);
        Assert.Equal(3f, second.MeanDo, 1e-4f);
        Assert.Equal(3f, second.LayerMax[0], 1e-4f);
        Assert.Equal(8f, stats.PreviousDay!.MeanDo, 1e-4f);
    }

    [Fact]
    public void RollingMeanAndSteadyState()
    {
        var stats = new DailyStats(new SimConfig(), 2);
        AddDay(stats, 4f, 0.3f);
        Assert.Equal(4f, stats.RollingMeanDo, 1e-4f);
        Assert.Equal(0.3f, stats.RollingHypoxicFraction, 1e-4f);
        Assert.False(stats.IsSteady(0.01f));

        AddDay(stats, 4.005f, 0.3f);
        Assert.True(stats.IsSteady(0.01f));
    }

    [Fact]
    public void ResetClearsEverything()
    {
        var stats = new DailyStats(new SimConfig(), 2);
        AddDay(stats, 4f, 0.3f);
        stats.Add(Tick(9f, 0f), [9f, 9f]);

        stats.Reset();

        Assert.Null(stats.LastDay);
        Assert.Equal(0f, stats.RollingMeanDo);
        var day = AddDay(stats, 2f, 0.1f);
        Assert.Equal(0, day!.Day);
        Assert.Equal(2f, day.MeanDo, 1e-4f);
    }

    [Fact]
    public void DoGainPerKwhHandlesZeroEnergy()
    {
        Assert.Equal(0.5f, DailyStats.DoGainPerKwh(4f, 6f, 4f), 1e-4f);
        Assert.Equal(0f, DailyStats.DoGainPerKwh(4f, 6f, 0f));
    }
}
