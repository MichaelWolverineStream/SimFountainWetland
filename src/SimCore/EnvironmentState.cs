namespace SimCore;

public sealed class EnvironmentState
{
    public Season Season { get; set; } = Season.Spring;
    public Wind Wind { get; set; } = Wind.Moderate;
    public bool Rain { get; set; }
    public bool AlgaeBloom { get; set; }

    public int Day { get; private set; }
    public int Hour { get; private set; }

    public void Advance()
    {
        Hour++;
        if (Hour < 24) return;
        Hour = 0;
        Day++;
    }

    public void ResetClock()
    {
        Day = 0;
        Hour = 0;
    }

    // Half-sine daylight curve centred on noon, sampled at the middle of the current hour.
    public float Light(float photoperiodHours)
    {
        float sinceSunrise = Hour + 0.5f - (12f - photoperiodHours / 2f);
        if (sinceSunrise <= 0f || sinceSunrise >= photoperiodHours) return 0f;
        return MathF.Sin(MathF.PI * sinceSunrise / photoperiodHours);
    }
}
