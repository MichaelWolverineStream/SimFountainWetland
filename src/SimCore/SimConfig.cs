namespace SimCore;

public enum Season { Spring, Summer, Autumn, Winter }

public enum Wind { Calm, Moderate, High }

public readonly record struct SeasonParams(float DoSat, float Theta, float PhotoperiodHours);

// Rates are per tick; defaults assume TickHours = 1.
public sealed class SimConfig
{
    public float CellSizeXZ { get; set; } = 2.0f;
    public float CellSizeY { get; set; } = 0.25f;
    public float TickHours { get; set; } = 1.0f;

    public SeasonParams Spring { get; set; } = new(10f, 1.0f, 13f);
    public SeasonParams Summer { get; set; } = new(8f, 1.6f, 15f);
    public SeasonParams Autumn { get; set; } = new(10f, 0.9f, 11f);
    public SeasonParams Winter { get; set; } = new(14f, 0.4f, 9f);

    public float WindCalm { get; set; } = 0.5f;
    public float WindModerate { get; set; } = 1.0f;
    public float WindHigh { get; set; } = 1.5f;

    public float SurfaceReaeration { get; set; } = 0.08f;
    public float DiffusionH { get; set; } = 0.10f;
    public float DiffusionV { get; set; } = 0.01f;

    public float RainDiffusionVMultiplier { get; set; } = 8f;
    public float RainRelaxation { get; set; } = 0.15f;
    public int RainLayers { get; set; } = 2;

    public float Bod { get; set; } = 0.004f;
    public float Sod { get; set; } = 0.15f;
    public float SodHalfSaturation { get; set; } = 1.0f;

    public float PhotosynthesisMax { get; set; } = 0.25f;
    public float LightExtinction { get; set; } = 1.2f;

    public float BloomPhotosynthesisMultiplier { get; set; } = 3f;
    public float BloomBodMultiplier { get; set; } = 4f;
    public float BloomExtinctionMultiplier { get; set; } = 3f;

    public float DoCap { get; set; } = 20f;
    public float InitialSaturationFraction { get; set; } = 0.9f;

    public float SprayHeightM { get; set; } = 2f;
    public float SprayEfficiency { get; set; } = 0.7f;
    public float PumpEfficiency { get; set; } = 0.5f;
    // Head loss per metre of pipe at PipeReferenceLpm; scales with flow squared.
    public float PipeFrictionPerMeter { get; set; } = 0.04f;
    public float PipeReferenceLpm { get; set; } = 1000f;
    public float MaxLpm { get; set; } = 3000f;
    // Calibrated on the real level: Summer/Calm passes at ~2500 L/min, Spring/Autumn at ~1500 L/min.
    public float PumpZoneLpmPerRadius { get; set; } = 100f;
    public float SprayLpmPerRadius { get; set; } = 1000f;
    public float PumpZoneDiffusionVMultiplier { get; set; } = 5f;
    public int MaxAdvectionSubsteps { get; set; } = 16;

    public float HypoxiaThreshold { get; set; } = 2f;
    public float TargetMeanDo { get; set; } = 6f;
    public float MaxHypoxicFraction { get; set; } = 0.10f;
    public int WindowTicks { get; set; } = 24;
    public int RequiredPassDays { get; set; } = 3;

    public float CellVolumeM3 => CellSizeXZ * CellSizeXZ * CellSizeY;

    public float MaxStableDiffusionV => (1f - 4f * DiffusionH) / 2f;

    public SeasonParams GetSeason(Season season) => season switch
    {
        Season.Spring => Spring,
        Season.Summer => Summer,
        Season.Autumn => Autumn,
        Season.Winter => Winter,
        _ => throw new ArgumentOutOfRangeException(nameof(season)),
    };

    public float GetWindMultiplier(Wind wind) => wind switch
    {
        Wind.Calm => WindCalm,
        Wind.Moderate => WindModerate,
        Wind.High => WindHigh,
        _ => throw new ArgumentOutOfRangeException(nameof(wind)),
    };

    public void Validate()
    {
        if (DiffusionH < 0f || DiffusionV < 0f || 4f * DiffusionH + 2f * DiffusionV > 1f)
            throw new InvalidOperationException("Diffusion is unstable: requires D_h, D_v >= 0 and 4*D_h + 2*D_v <= 1.");
        if (SodHalfSaturation <= 0f)
            throw new InvalidOperationException("SodHalfSaturation must be > 0.");
        if (PumpEfficiency <= 0f)
            throw new InvalidOperationException("PumpEfficiency must be > 0.");
        if (WindowTicks <= 0 || TickHours <= 0f)
            throw new InvalidOperationException("WindowTicks and TickHours must be > 0.");
    }
}
