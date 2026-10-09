namespace SimCore;

// Averages over one day of ticks; Min/Max and the layer min/max span the day's hourly values.
public sealed record DaySummary(
    int Day,
    float MeanDo,
    float MinDo,
    float MaxDo,
    float SurfaceMeanDo,
    float BottomMeanDo,
    float HypoxicFraction,
    float TotalDoKg,
    float EnergyKwh,
    float[] LayerMean,
    float[] LayerMin,
    float[] LayerMax);

public sealed class DailyStats
{
    readonly SimConfig _config;
    readonly float[] _ringDo;
    readonly float[] _ringHypoxic;
    readonly double[] _layerSum;
    readonly float[] _layerMin;
    readonly float[] _layerMax;
    int _ringCount;
    int _ringHead;
    int _ticksInDay;
    int _day;
    double _sumDo, _sumSurface, _sumBottom, _sumHypoxic, _sumKg, _sumKwh;
    float _minDo, _maxDo;

    public DailyStats(SimConfig config, int layerCount)
    {
        _config = config;
        _ringDo = new float[config.WindowTicks];
        _ringHypoxic = new float[config.WindowTicks];
        _layerSum = new double[layerCount];
        _layerMin = new float[layerCount];
        _layerMax = new float[layerCount];
        Reset();
    }

    public float RollingMeanDo { get; private set; }
    public float RollingHypoxicFraction { get; private set; }
    public DaySummary? LastDay { get; private set; }
    public DaySummary? PreviousDay { get; private set; }

    public bool IsSteady(float tolerance) =>
        LastDay is { } last && PreviousDay is { } prev && MathF.Abs(last.MeanDo - prev.MeanDo) < tolerance;

    // Returns the completed day's summary when the tick closes a window.
    public DaySummary? Add(in SimStats stats, ReadOnlySpan<float> layerMeans)
    {
        _ringDo[_ringHead] = stats.MeanDo;
        _ringHypoxic[_ringHead] = stats.HypoxicFraction;
        _ringHead = (_ringHead + 1) % _ringDo.Length;
        _ringCount = Math.Min(_ringCount + 1, _ringDo.Length);

        double ringDo = 0, ringHyp = 0;
        for (int i = 0; i < _ringCount; i++) { ringDo += _ringDo[i]; ringHyp += _ringHypoxic[i]; }
        RollingMeanDo = (float)(ringDo / _ringCount);
        RollingHypoxicFraction = (float)(ringHyp / _ringCount);

        _sumDo += stats.MeanDo;
        _sumSurface += stats.SurfaceMeanDo;
        _sumBottom += stats.BottomMeanDo;
        _sumHypoxic += stats.HypoxicFraction;
        _sumKg += stats.TotalDoKg;
        _sumKwh += stats.EnergyKwh;
        _minDo = MathF.Min(_minDo, stats.MinDo);
        _maxDo = MathF.Max(_maxDo, stats.MaxDo);
        int layers = Math.Min(layerMeans.Length, _layerSum.Length);
        for (int l = 0; l < layers; l++)
        {
            float v = layerMeans[l];
            _layerSum[l] += v;
            _layerMin[l] = MathF.Min(_layerMin[l], v);
            _layerMax[l] = MathF.Max(_layerMax[l], v);
        }
        if (++_ticksInDay < _config.WindowTicks) return null;

        double n = _ticksInDay;
        var layerMean = new float[_layerSum.Length];
        for (int l = 0; l < layerMean.Length; l++) layerMean[l] = (float)(_layerSum[l] / n);
        var summary = new DaySummary(
            Day: _day,
            MeanDo: (float)(_sumDo / n),
            MinDo: _minDo,
            MaxDo: _maxDo,
            SurfaceMeanDo: (float)(_sumSurface / n),
            BottomMeanDo: (float)(_sumBottom / n),
            HypoxicFraction: (float)(_sumHypoxic / n),
            TotalDoKg: (float)(_sumKg / n),
            EnergyKwh: (float)_sumKwh,
            LayerMean: layerMean,
            LayerMin: (float[])_layerMin.Clone(),
            LayerMax: (float[])_layerMax.Clone());

        PreviousDay = LastDay;
        LastDay = summary;
        _day++;
        StartDay();
        return summary;
    }

    public void Reset()
    {
        Array.Clear(_ringDo);
        Array.Clear(_ringHypoxic);
        _ringCount = _ringHead = _day = 0;
        RollingMeanDo = RollingHypoxicFraction = 0f;
        LastDay = PreviousDay = null;
        StartDay();
    }

    void StartDay()
    {
        _ticksInDay = 0;
        _sumDo = _sumSurface = _sumBottom = _sumHypoxic = _sumKg = _sumKwh = 0;
        _minDo = float.MaxValue;
        _maxDo = float.MinValue;
        Array.Clear(_layerSum);
        Array.Fill(_layerMin, float.MaxValue);
        Array.Fill(_layerMax, float.MinValue);
    }

    // Change in mean DO per extra kWh/day; zero when the energy use did not change.
    public static float DoGainPerKwh(float baselineMeanDo, float meanDo, float extraKwh) =>
        MathF.Abs(extraKwh) > 1e-6f ? (meanDo - baselineMeanDo) / extraKwh : 0f;
}
