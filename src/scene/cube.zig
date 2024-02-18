const std = @import("std");
const zalgebra = @import("zalgebra");

const cube_vertices = [_][3]f32{
    .{ -1.0, -1.0, -1.0 },
    .{ 1.0, -1.0, -1.0 },
    .{ 1.0, 1.0, -1.0 },
    .{ -1.0, 1.0, -1.0 },
    .{ -1.0, -1.0, 1.0 },
    .{ 1.0, -1.0, 1.0 },
    .{ 1.0, 1.0, 1.0 },
    .{ -1.0, 1.0, 1.0 },
};

const cube_vertices_indices = [_][3]u16{
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 1, 5, 2 },
    .{ 2, 5, 6 },
    .{ 5, 4, 6 },
    .{ 6, 4, 7 },
    .{ 4, 0, 7 },
    .{ 7, 0, 3 },
    .{ 3, 2, 7 },
    .{ 7, 2, 6 },
    .{ 4, 5, 0 },
    .{ 0, 5, 1 },
};

const cube_uvs = [_][2]f32{
    .{ 0.0, 0.0 },
    .{ 1.0, 0.0 },
    .{ 1.0, 1.0 },
    .{ 0.0, 1.0 },
};

const cube_uvs_indices = [_][3]u16{
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
    .{ 0, 1, 3 },
    .{ 3, 1, 2 },
};

const cube_normals = [_][3]f32{
    .{ 0.0, 0.0, 1.0 },
    .{ -1.0, 0.0, 0.0 },
    .{ 0.0, 0.0, -1.0 },
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, -1.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
};

const cube_normals_indices = [_][3]u16{
    .{ 0, 0, 0 },
    .{ 0, 0, 0 },
    .{ 1, 1, 1 },
    .{ 1, 1, 1 },
    .{ 2, 2, 2 },
    .{ 2, 2, 2 },
    .{ 3, 3, 3 },
    .{ 3, 3, 3 },
    .{ 4, 4, 4 },
    .{ 4, 4, 4 },
    .{ 5, 5, 5 },
    .{ 5, 5, 5 },
};

pub fn get_cube_vertices() [12 * 3][3]f32 {
    var vertices: [12 * 3][3]f32 = undefined;

    const trianglecount = cube_vertices_indices.len;

    for (0..trianglecount) |triangleindex| {
        const triangle_vertices_indices = cube_vertices_indices[triangleindex];

        for (0..3) |i| {
            const vertex_index = triangle_vertices_indices[i];
            vertices[triangleindex * 3 + i] = cube_vertices[vertex_index];
        }
    }

    return vertices;
}

pub fn get_cube_normals() [12 * 3][3]f32 {
    var normals: [12 * 3][3]f32 = undefined;

    const trianglecount = cube_vertices_indices.len;

    for (0..trianglecount) |triangleindex| {
        const triangle_normal_indices = cube_normals_indices[triangleindex];

        for (0..3) |i| {
            const vertex_index = triangle_normal_indices[i];
            normals[triangleindex * 3 + i] = cube_normals[vertex_index];
        }
    }

    return normals;
}

pub fn get_cube_uvs() [12 * 3][2]f32 {
    var uvs: [12 * 3][2]f32 = undefined;

    const trianglecount = cube_vertices_indices.len;

    for (0..trianglecount) |triangleindex| {
        const triangle_normal_indices = cube_uvs_indices[triangleindex];

        for (0..3) |i| {
            const vertex_index = triangle_normal_indices[i];
            uvs[triangleindex * 3 + i] = cube_uvs[vertex_index];
        }
    }

    return uvs;
}
