using System;
using Godot;
using SimCore;

namespace SimFountainWetland.Game;

public static class GridMapVoxelizer
{
    // Every used GridMap cell is solid. Bounds cover the used cells and the water level;
    // `origin` maps grid coordinates back to GridMap coordinates (map = grid + origin).
    public static VoxelGrid Voxelize(GridMap gridMap, Vector3I seedCell, int waterLevelY, float cellHeightM, out Vector3I origin)
    {
        var used = gridMap.GetUsedCells();
        if (used.Count == 0)
            throw new InvalidOperationException("GridMap has no cells.");

        var min = used[0];
        var max = used[0];
        foreach (var c in used)
        {
            min = new Vector3I(Math.Min(min.X, c.X), Math.Min(min.Y, c.Y), Math.Min(min.Z, c.Z));
            max = new Vector3I(Math.Max(max.X, c.X), Math.Max(max.Y, c.Y), Math.Max(max.Z, c.Z));
        }
        max.Y = Math.Max(max.Y, waterLevelY);

        int sizeX = max.X - min.X + 1;
        int sizeY = max.Y - min.Y + 1;
        int sizeZ = max.Z - min.Z + 1;
        var solid = new bool[sizeX * sizeY * sizeZ];
        foreach (var c in used)
            solid[(c.X - min.X) + sizeX * ((c.Z - min.Z) + sizeZ * (c.Y - min.Y))] = true;

        origin = min;
        var seed = new Int3(seedCell.X - min.X, seedCell.Y - min.Y, seedCell.Z - min.Z);
        return VoxelGrid.FromSolidMask(solid, sizeX, sizeY, sizeZ, seed, waterLevelY - min.Y, cellHeightM);
    }
}
