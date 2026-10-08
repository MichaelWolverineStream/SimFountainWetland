namespace SimCore;

public readonly record struct SimStats(
    long Tick,
    int Day,
    int Hour,
    float MeanDo,
    float MinDo,
    float MaxDo,
    float SurfaceMeanDo,
    float BottomMeanDo,
    float TotalDoKg,
    float HypoxicFraction,
    float PowerKw,
    float EnergyKwh);
