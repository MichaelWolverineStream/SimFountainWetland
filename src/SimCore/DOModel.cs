namespace SimCore;

public sealed class DOModel
{
    readonly float[] _bedWeight;
    readonly float[] _dvMultiplier;
    readonly float[] _layerPhotoFactor;
    readonly double[] _layerSum;
    readonly int[] _layerCount;
    float[] _scratch;
    int _appliedZoneVersion = -1;

    public DOModel(VoxelGrid grid, SimConfig config, EnvironmentState? environment = null)
    {
        config.Validate();
        Grid = grid;
        Config = config;
        Environment = environment ?? new EnvironmentState();
        Fountains = new FountainSet(grid, config);

        int n = grid.WaterCount;
        Do = new float[n];
        _scratch = new float[n];
        _dvMultiplier = new float[n];
        Array.Fill(_dvMultiplier, 1f);

        // Side faces are CellSizeY x CellSizeXZ, so they weigh less than the CellSizeXZ^2 floor face.
        float sideWeight = config.CellSizeY / config.CellSizeXZ;
        _bedWeight = new float[n];
        for (int i = 0; i < n; i++)
            _bedWeight[i] = (grid.IsBottom(i) ? 1f : 0f) + grid.SideBedFaces[i] * sideWeight;

        _layerPhotoFactor = new float[grid.LayerCount];
        _layerSum = new double[grid.LayerCount];
        _layerCount = new int[grid.LayerCount];
        for (int i = 0; i < n; i++) _layerCount[grid.DepthLayer[i]]++;
        LayerMeans = new float[grid.LayerCount];

        Reset();
    }

    public VoxelGrid Grid { get; }
    public SimConfig Config { get; }
    public EnvironmentState Environment { get; }
    public FountainSet Fountains { get; }

    // Swapped every tick; re-read after Step().
    public float[] Do { get; private set; }
    public float[] LayerMeans { get; }
    public SimStats Stats { get; private set; }
    public long TickCount { get; private set; }

    public void Reset()
    {
        float initial = Config.InitialSaturationFraction * Config.GetSeason(Environment.Season).DoSat;
        Array.Fill(Do, initial);
        Environment.ResetClock();
        TickCount = 0;
        ComputeStats(0f);
    }

    public void Step()
    {
        var season = Config.GetSeason(Environment.Season);
        bool bloom = Environment.AlgaeBloom;

        SyncPumpZone();
        ApplySources(season, bloom);
        Fountains.Apply(Do, season.DoSat);
        Clamp();
        Diffuse(Environment.Rain ? Config.RainDiffusionVMultiplier : 1f);

        ComputeStats(Fountains.PowerKw * Config.TickHours);
        Environment.Advance();
        TickCount++;
    }

    void ApplySources(SeasonParams season, bool bloom)
    {
        float light = Environment.Light(season.PhotoperiodHours);
        float pMax = Config.PhotosynthesisMax * (bloom ? Config.BloomPhotosynthesisMultiplier : 1f);
        float kExt = Config.LightExtinction * (bloom ? Config.BloomExtinctionMultiplier : 1f);
        for (int layer = 0; layer < _layerPhotoFactor.Length; layer++)
        {
            float depth = (layer + 0.5f) * Config.CellSizeY;
            _layerPhotoFactor[layer] = pMax * light * MathF.Exp(-kExt * depth);
        }

        float bod = Config.Bod * season.Theta * (bloom ? Config.BloomBodMultiplier : 1f);
        float sod = Config.Sod * season.Theta;
        float halfSat = Config.SodHalfSaturation;
        float doSat = season.DoSat;
        float surface = Config.SurfaceReaeration * Config.GetWindMultiplier(Environment.Wind);
        float rain = Environment.Rain ? Config.RainRelaxation : 0f;
        int rainLayers = Config.RainLayers;

        var values = Do;
        var layers = Grid.DepthLayer;
        for (int i = 0; i < values.Length; i++)
        {
            float c = values[i];
            int layer = layers[i];
            c += _layerPhotoFactor[layer];
            c -= bod * c;
            float bed = _bedWeight[i];
            if (bed > 0f && c > 0f) c -= MathF.Min(c, sod * bed * c / (c + halfSat));
            if (layer == 0) c += surface * (doSat - c);
            if (layer < rainLayers) c += rain * (doSat - c);
            values[i] = c;
        }
    }

    void Clamp()
    {
        float cap = Config.DoCap;
        var values = Do;
        for (int i = 0; i < values.Length; i++)
            values[i] = Math.Clamp(values[i], 0f, cap);
    }

    void SyncPumpZone()
    {
        int version = Fountains.Version;
        if (version == _appliedZoneVersion) return;
        _appliedZoneVersion = version;

        Array.Fill(_dvMultiplier, 1f);
        foreach (var unit in Fountains.Units)
        {
            if (!unit.IsActive) continue;
            foreach (var column in unit.PumpZoneColumns)
                foreach (int cell in column)
                    _dvMultiplier[cell] = Config.PumpZoneDiffusionVMultiplier;
        }
    }

    // Explicit anisotropic diffusion; per-link coefficients are symmetric so total DO is conserved.
    void Diffuse(float verticalMultiplier)
    {
        float dh = Config.DiffusionH;
        float dvBase = Config.DiffusionV * verticalMultiplier;
        float dvMax = Config.MaxStableDiffusionV;
        var nb = Grid.Neighbors;
        var src = Do;
        var dst = _scratch;
        var m = _dvMultiplier;

        for (int i = 0; i < src.Length; i++)
        {
            int b = i * 6;
            float c = src[i];
            float horizontal = src[nb[b]] + src[nb[b + 1]] + src[nb[b + 2]] + src[nb[b + 3]] - 4f * c;
            int down = nb[b + VoxelGrid.Down];
            int up = nb[b + VoxelGrid.Up];
            float dvDown = MathF.Min(dvBase * MathF.Max(m[i], m[down]), dvMax);
            float dvUp = MathF.Min(dvBase * MathF.Max(m[i], m[up]), dvMax);
            dst[i] = c + dh * horizontal + dvDown * (src[down] - c) + dvUp * (src[up] - c);
        }

        _scratch = src;
        Do = dst;
    }

    void ComputeStats(float energyKwh)
    {
        var values = Do;
        Array.Clear(_layerSum);
        double sum = 0, bottomSum = 0;
        int bottomCount = 0, hypoxic = 0;
        float min = float.MaxValue, max = float.MinValue;
        float threshold = Config.HypoxiaThreshold;

        for (int i = 0; i < values.Length; i++)
        {
            float c = values[i];
            sum += c;
            _layerSum[Grid.DepthLayer[i]] += c;
            if (Grid.IsBottom(i)) { bottomSum += c; bottomCount++; }
            if (c < threshold) hypoxic++;
            if (c < min) min = c;
            if (c > max) max = c;
        }

        for (int l = 0; l < LayerMeans.Length; l++)
            LayerMeans[l] = _layerCount[l] > 0 ? (float)(_layerSum[l] / _layerCount[l]) : 0f;

        int n = Math.Max(1, values.Length);
        Stats = new SimStats(
            Tick: TickCount,
            Day: Environment.Day,
            Hour: Environment.Hour,
            MeanDo: (float)(sum / n),
            MinDo: values.Length > 0 ? min : 0f,
            MaxDo: values.Length > 0 ? max : 0f,
            SurfaceMeanDo: LayerMeans.Length > 0 ? LayerMeans[0] : 0f,
            BottomMeanDo: bottomCount > 0 ? (float)(bottomSum / bottomCount) : 0f,
            TotalDoKg: (float)(sum * Config.CellVolumeM3 * 1e-3),
            HypoxicFraction: (float)hypoxic / n,
            PowerKw: Fountains.PowerKw,
            EnergyKwh: energyKwh);
    }
}
