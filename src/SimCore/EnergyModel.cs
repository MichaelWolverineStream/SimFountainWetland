namespace SimCore;

public static class EnergyModel
{
    public const float WaterDensity = 1000f;
    public const float Gravity = 9.81f;

    public static float FlowM3PerSecond(float lpm) => lpm / 60000f;

    public static float PowerKw(float lpm, float headM, float pumpEfficiency) =>
        WaterDensity * Gravity * FlowM3PerSecond(lpm) * headM / pumpEfficiency / 1000f;

    public static float FrictionHeadM(float pipeLengthM, float lpm, float frictionPerMeter, float referenceLpm)
    {
        float ratio = lpm / referenceLpm;
        return frictionPerMeter * pipeLengthM * ratio * ratio;
    }
}
