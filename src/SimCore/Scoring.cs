namespace SimCore;

public readonly record struct DayResult(int Day, float MeanDo, float HypoxicFraction, float EnergyKwh, bool Passed);

public sealed class Scoring
{
    readonly SimConfig _config;
    readonly float[] _ringDo;
    readonly float[] _ringHypoxic;
    int _ringCount;
    int _ringHead;
    int _ticksInDay;
    int _day;
    double _daySumDo;
    double _daySumHypoxic;
    double _dayKwh;

    public Scoring(SimConfig config)
    {
        _config = config;
        _ringDo = new float[config.WindowTicks];
        _ringHypoxic = new float[config.WindowTicks];
    }

    public float RollingMeanDo { get; private set; }
    public float RollingHypoxicFraction { get; private set; }
    public int PassStreakDays { get; private set; }
    public bool Passed => PassStreakDays >= _config.RequiredPassDays;
    public DayResult? LastDay { get; private set; }
    public DayResult? PreviousDay { get; private set; }

    public bool IsSteady(float tolerance) =>
        LastDay is { } last && PreviousDay is { } prev && MathF.Abs(last.MeanDo - prev.MeanDo) < tolerance;

    // Returns the completed day's result when the tick closes an evaluation window.
    public DayResult? Add(in SimStats stats)
    {
        _ringDo[_ringHead] = stats.MeanDo;
        _ringHypoxic[_ringHead] = stats.HypoxicFraction;
        _ringHead = (_ringHead + 1) % _ringDo.Length;
        _ringCount = Math.Min(_ringCount + 1, _ringDo.Length);

        double sumDo = 0, sumHyp = 0;
        for (int i = 0; i < _ringCount; i++) { sumDo += _ringDo[i]; sumHyp += _ringHypoxic[i]; }
        RollingMeanDo = (float)(sumDo / _ringCount);
        RollingHypoxicFraction = (float)(sumHyp / _ringCount);

        _daySumDo += stats.MeanDo;
        _daySumHypoxic += stats.HypoxicFraction;
        _dayKwh += stats.EnergyKwh;
        if (++_ticksInDay < _config.WindowTicks) return null;

        float meanDo = (float)(_daySumDo / _ticksInDay);
        float hypoxic = (float)(_daySumHypoxic / _ticksInDay);
        bool passed = meanDo >= _config.TargetMeanDo && hypoxic <= _config.MaxHypoxicFraction;
        var result = new DayResult(_day, meanDo, hypoxic, (float)_dayKwh, passed);

        PassStreakDays = passed ? PassStreakDays + 1 : 0;
        PreviousDay = LastDay;
        LastDay = result;
        _day++;
        _ticksInDay = 0;
        _daySumDo = _daySumHypoxic = _dayKwh = 0;
        return result;
    }

    public void Reset()
    {
        Array.Clear(_ringDo);
        Array.Clear(_ringHypoxic);
        _ringCount = _ringHead = _ticksInDay = _day = 0;
        _daySumDo = _daySumHypoxic = _dayKwh = 0;
        RollingMeanDo = RollingHypoxicFraction = 0f;
        PassStreakDays = 0;
        LastDay = PreviousDay = null;
    }

    public static float DoGainPerKwh(float baselineMeanDo, float meanDo, float kwhPerDay) =>
        kwhPerDay > 0f ? (meanDo - baselineMeanDo) / kwhPerDay : 0f;
}
