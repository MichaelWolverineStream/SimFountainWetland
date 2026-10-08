using SimCore;

namespace SimCore.Tests;

public class EnvironmentStateTests
{
    [Fact]
    public void LightIsZeroAtNightAndPeaksAtNoon()
    {
        var env = new EnvironmentState();
        Assert.Equal(0f, env.Light(13f));

        for (int h = 0; h < 12; h++) env.Advance();
        Assert.True(env.Light(13f) > 0.95f);
    }

    [Fact]
    public void ClockRollsOverDays()
    {
        var env = new EnvironmentState();
        for (int h = 0; h < 25; h++) env.Advance();
        Assert.Equal(1, env.Day);
        Assert.Equal(1, env.Hour);
    }
}
