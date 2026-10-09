using Godot;
using SimCore;

namespace SimFountainWetland.Game;

// One opaque cube per water cell. INSTANCE_CUSTOM: r = DO (mg/L, updated every tick),
// g = water depth of the cell's column in cells, b = depth of the cell below the surface in cells.
// do_voxel.gdshader colours by DO (Oxygen view) or by depth (Nature view).
public partial class WaterVoxelRenderer : MultiMeshInstance3D
{
    // 12 transform floats (3x4, row-major) + 4 custom-data floats per instance.
    const int Stride = 16;
    const int CustomOffset = 12;

    [Export] public Material? VoxelMaterial { get; set; }

    float[] _buffer = [];

    public void Build(VoxelGrid grid, Vector3I origin)
    {
        var mesh = new BoxMesh { Size = Vector3.One, Material = VoxelMaterial };
        // Format and custom data must be configured before InstanceCount allocates the buffer.
        var multimesh = new MultiMesh
        {
            TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
            UseCustomData = true,
            Mesh = mesh,
        };
        multimesh.InstanceCount = grid.WaterCount;

        _buffer = new float[grid.WaterCount * Stride];
        for (int i = 0; i < grid.WaterCount; i++)
        {
            var p = grid.WaterCoords(i);
            int b = i * Stride;
            _buffer[b + 0] = 1f;
            _buffer[b + 3] = p.X + origin.X + 0.5f;
            _buffer[b + 5] = 1f;
            _buffer[b + 7] = p.Y + origin.Y + 0.5f;
            _buffer[b + 10] = 1f;
            _buffer[b + 11] = p.Z + origin.Z + 0.5f;
            int top = grid.ColumnTop(p.X, p.Z);
            int bottom = grid.ColumnBottom(p.X, p.Z);
            _buffer[b + CustomOffset + 1] = top >= 0 && bottom >= 0 ? top - bottom + 1 : 1f;
            _buffer[b + CustomOffset + 2] = grid.DepthLayer[i];
        }

        multimesh.CustomAabb = new Aabb(origin, new Vector3(grid.SizeX, grid.SizeY, grid.SizeZ));
        multimesh.Buffer = _buffer;
        Multimesh = multimesh;
    }

    public void UpdateValues(float[] values)
    {
        if (Multimesh == null || values.Length * Stride != _buffer.Length) return;
        for (int i = 0; i < values.Length; i++)
            _buffer[i * Stride + CustomOffset] = values[i];
        Multimesh.Buffer = _buffer;
    }
}
