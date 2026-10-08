using SimCore;

namespace SimCore.Tests;

public class InfoTests
{
    [Fact]
    public void RunsOnDotNet10()
    {
        Assert.StartsWith("10.", Info.RuntimeVersion);
    }
}
