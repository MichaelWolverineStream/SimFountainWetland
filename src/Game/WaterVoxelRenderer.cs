using System;
using System.Buffers.Binary;
using Godot;
using SimCore;

namespace SimFountainWetland.Game;

// One opaque cube per water cell. INSTANCE_CUSTOM: r = DO (mg/L, updated every tick),
// g = water depth of the cell's column in cells, b = depth of the cell below the surface in cells.
// column_do texture: one RGH texel per (x, z) column, r = depth-averaged DO, g = 1 where there is water.
// do_voxel.gdshader colours by DO (Oxygen view) or by depth (Nature view).
public partial class WaterVoxelRenderer : MultiMeshInstance3D
{
    // 12 transform floats (3x4, row-major) + 4 custom-data floats per instance.
    const int Stride = 16;
    const int CustomOffset = 12;
    const int TexelBytes = 4;

    [Export] public Material? VoxelMaterial { get; set; }

    float[] _buffer = [];
    VoxelGrid? _grid;
    float[] _columnMeans = [];
    byte[] _texels = [];
    Image? _columnImage;
    ImageTexture? _columnTexture;

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
            int bottom = grid.ColumnBottom(p.X, p.Z);
            _buffer[b + CustomOffset + 1] = bottom >= 0 ? grid.DepthLayer[bottom] + 1 : 1f;
            _buffer[b + CustomOffset + 2] = grid.DepthLayer[i];
        }

        multimesh.CustomAabb = new Aabb(origin, new Vector3(grid.SizeX, grid.SizeY, grid.SizeZ));
        multimesh.Buffer = _buffer;
        Multimesh = multimesh;

        _grid = grid;
        _columnMeans = new float[grid.SizeX * grid.SizeZ];
        _texels = new byte[_columnMeans.Length * TexelBytes];
        _columnImage = Image.CreateFromData(grid.SizeX, grid.SizeZ, false, Image.Format.Rgh, _texels);
        _columnTexture = ImageTexture.CreateFromImage(_columnImage);
        if (VoxelMaterial is ShaderMaterial material)
        {
            material.SetShaderParameter("column_do", _columnTexture);
            material.SetShaderParameter("column_origin", new Vector2(origin.X, origin.Z));
            material.SetShaderParameter("column_size", new Vector2(grid.SizeX, grid.SizeZ));
        }
    }

    public void UpdateValues(float[] values)
    {
        if (Multimesh == null || values.Length * Stride != _buffer.Length) return;
        for (int i = 0; i < values.Length; i++)
            _buffer[i * Stride + CustomOffset] = values[i];
        Multimesh.Buffer = _buffer;

        if (_grid == null || _columnImage == null || _columnTexture == null) return;
        _grid.ColumnMeans(values, _columnMeans);
        var texels = _texels.AsSpan();
        for (int c = 0; c < _columnMeans.Length; c++)
        {
            float mean = _columnMeans[c];
            bool wet = !float.IsNaN(mean);
            var texel = texels.Slice(c * TexelBytes, TexelBytes);
            BinaryPrimitives.WriteHalfLittleEndian(texel, wet ? (Half)mean : Half.Zero);
            BinaryPrimitives.WriteHalfLittleEndian(texel[2..], wet ? Half.One : Half.Zero);
        }
        _columnImage.SetData(_grid.SizeX, _grid.SizeZ, false, Image.Format.Rgh, _texels);
        _columnTexture.Update(_columnImage);
    }
}
