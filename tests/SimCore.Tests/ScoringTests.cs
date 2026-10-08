using SimCore;

namespace SimCore.Tests;

public class ScoringTests
{
    static SimStats Tick(float meanDo, float hypoxic, float kwh = 1f) =>
        new(0, 0, 0, meanDo, 0f, 0f, 0f, 0f, 0f, hypoxic, 0f, kwh);

    static void AddDay(Scoring scoring, float meanDo, float hypoxic)
    {
        for (int t = 0; t < 24; t++) scoring.Add(Tick(meanDo, hypoxic));
    }

    [Fact]
    public void PassesAfterRequiredConsecutiveDays()
    {
        var scoring = new Scoring(new SimConfig());
        AddDay(scoring, 7f, 0.05f);
        AddDay(scoring, 7f, 0.05f);
        Assert.False(scoring.Passed);

        AddDay(scoring, 7f, 0.05f);
        Assert.True(scoring.Passed);
        Assert.Equal(24f, scoring.LastDay!.Value.EnergyKwh, 1e-4f);
    }

    [Fact]
    public void FailingDayResetsStreak()
    {
        var scoring = new Scoring(new SimConfig());
        AddDay(scoring, 7f, 0.05f);
        AddDay(scoring, 7f, 0.05f);
        AddDay(scoring, 7f, 0.25f);
        Assert.Equal(0, scoring.PassStreakDays);

        AddDay(scoring, 5f, 0.05f);
        Assert.Equal(0, scoring.PassStreakDays);
        Assert.False(scoring.Passed);
    }

    [Fact]
    public void RollingMeanAndSteadyState()
    {
        var scoring = new Scoring(new SimConfig());
        AddDay(scoring, 4f, 0.3f);
        Assert.Equal(4f, scoring.RollingMeanDo, 1e-4f);
        Assert.False(scoring.IsSteady(0.01f));

        AddDay(scoring, 4.005f, 0.3f);
        Assert.True(scoring.IsSteady(0.01f));
    }

    [Fact]
    public void DoGainPerKwhHandlesZeroEnergy()
    {
        Assert.Equal(0.5f, Scoring.DoGainPerKwh(4f, 6f, 4f), 1e-4f);
        Assert.Equal(0f, Scoring.DoGainPerKwh(4f, 6f, 0f));
    }
}
