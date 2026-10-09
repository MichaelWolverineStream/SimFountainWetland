using Godot;
using SimCore;

namespace SimFountainWetland.Game;

// Editor-tunable mirror of SimConfig. Seasons are (DO_sat mg/L, theta, photoperiod h).
[GlobalClass]
public partial class SimParamsResource : Resource
{
    static readonly SimConfig D = new();

    [ExportGroup("Cell and tick")]
    [Export] public float CellSizeXZ { get; set; } = D.CellSizeXZ;
    [Export] public float CellSizeY { get; set; } = D.CellSizeY;
    [Export] public float TickHours { get; set; } = D.TickHours;

    [ExportGroup("Seasons")]
    [Export] public Vector3 Spring { get; set; } = ToVector(D.Spring);
    [Export] public Vector3 Summer { get; set; } = ToVector(D.Summer);
    [Export] public Vector3 Autumn { get; set; } = ToVector(D.Autumn);
    [Export] public Vector3 Winter { get; set; } = ToVector(D.Winter);

    [ExportGroup("Wind")]
    [Export] public float WindCalm { get; set; } = D.WindCalm;
    [Export] public float WindModerate { get; set; } = D.WindModerate;
    [Export] public float WindHigh { get; set; } = D.WindHigh;

    [ExportGroup("Mixing")]
    [Export] public float SurfaceReaeration { get; set; } = D.SurfaceReaeration;
    [Export] public float DiffusionH { get; set; } = D.DiffusionH;
    [Export] public float DiffusionV { get; set; } = D.DiffusionV;

    [ExportGroup("Rain")]
    [Export] public float RainDiffusionVMultiplier { get; set; } = D.RainDiffusionVMultiplier;
    [Export] public float RainRelaxation { get; set; } = D.RainRelaxation;
    [Export] public int RainLayers { get; set; } = D.RainLayers;

    [ExportGroup("Biology")]
    [Export] public float Bod { get; set; } = D.Bod;
    [Export] public float Sod { get; set; } = D.Sod;
    [Export] public float SodHalfSaturation { get; set; } = D.SodHalfSaturation;
    [Export] public float PhotosynthesisMax { get; set; } = D.PhotosynthesisMax;
    [Export] public float LightExtinction { get; set; } = D.LightExtinction;
    [Export] public float BloomPhotosynthesisMultiplier { get; set; } = D.BloomPhotosynthesisMultiplier;
    [Export] public float BloomBodMultiplier { get; set; } = D.BloomBodMultiplier;
    [Export] public float BloomExtinctionMultiplier { get; set; } = D.BloomExtinctionMultiplier;
    [Export] public float DoCap { get; set; } = D.DoCap;
    [Export] public float InitialSaturationFraction { get; set; } = D.InitialSaturationFraction;

    [ExportGroup("Fountain")]
    [Export] public float SprayHeightM { get; set; } = D.SprayHeightM;
    [Export] public float SprayEfficiency { get; set; } = D.SprayEfficiency;
    [Export] public float PumpEfficiency { get; set; } = D.PumpEfficiency;
    [Export] public float PipeFrictionPerMeter { get; set; } = D.PipeFrictionPerMeter;
    [Export] public float PipeReferenceLpm { get; set; } = D.PipeReferenceLpm;
    [Export] public float MaxLpm { get; set; } = D.MaxLpm;
    [Export] public float PumpZoneLpmPerRadius { get; set; } = D.PumpZoneLpmPerRadius;
    [Export] public float SprayLpmPerRadius { get; set; } = D.SprayLpmPerRadius;
    [Export] public float PumpZoneDiffusionVMultiplier { get; set; } = D.PumpZoneDiffusionVMultiplier;
    [Export] public int MaxAdvectionSubsteps { get; set; } = D.MaxAdvectionSubsteps;

    [ExportGroup("Statistics")]
    [Export] public float HypoxiaThreshold { get; set; } = D.HypoxiaThreshold;
    [Export] public int WindowTicks { get; set; } = D.WindowTicks;

    public SimConfig ToConfig() => new()
    {
        CellSizeXZ = CellSizeXZ,
        CellSizeY = CellSizeY,
        TickHours = TickHours,
        Spring = ToSeason(Spring),
        Summer = ToSeason(Summer),
        Autumn = ToSeason(Autumn),
        Winter = ToSeason(Winter),
        WindCalm = WindCalm,
        WindModerate = WindModerate,
        WindHigh = WindHigh,
        SurfaceReaeration = SurfaceReaeration,
        DiffusionH = DiffusionH,
        DiffusionV = DiffusionV,
        RainDiffusionVMultiplier = RainDiffusionVMultiplier,
        RainRelaxation = RainRelaxation,
        RainLayers = RainLayers,
        Bod = Bod,
        Sod = Sod,
        SodHalfSaturation = SodHalfSaturation,
        PhotosynthesisMax = PhotosynthesisMax,
        LightExtinction = LightExtinction,
        BloomPhotosynthesisMultiplier = BloomPhotosynthesisMultiplier,
        BloomBodMultiplier = BloomBodMultiplier,
        BloomExtinctionMultiplier = BloomExtinctionMultiplier,
        DoCap = DoCap,
        InitialSaturationFraction = InitialSaturationFraction,
        SprayHeightM = SprayHeightM,
        SprayEfficiency = SprayEfficiency,
        PumpEfficiency = PumpEfficiency,
        PipeFrictionPerMeter = PipeFrictionPerMeter,
        PipeReferenceLpm = PipeReferenceLpm,
        MaxLpm = MaxLpm,
        PumpZoneLpmPerRadius = PumpZoneLpmPerRadius,
        SprayLpmPerRadius = SprayLpmPerRadius,
        PumpZoneDiffusionVMultiplier = PumpZoneDiffusionVMultiplier,
        MaxAdvectionSubsteps = MaxAdvectionSubsteps,
        HypoxiaThreshold = HypoxiaThreshold,
        WindowTicks = WindowTicks,
    };

    static Vector3 ToVector(SeasonParams s) => new(s.DoSat, s.Theta, s.PhotoperiodHours);

    static SeasonParams ToSeason(Vector3 v) => new(v.X, v.Y, v.Z);
}
