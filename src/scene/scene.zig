const zalgebra = @import("zalgebra");

pub const MaterialName = enum(u32) {
    Phong = 0,
    Pbr = 1,
};

pub const PhongDescriptor = extern struct {
    diffuse_color: zalgebra.Vec3,
    // diffuse_texture: *anyopaque,
};

pub const Material = extern struct {
    name: MaterialName,
    descriptor: extern union {
        phong: PhongDescriptor,
    },
};

pub const Mesh = extern struct {
    vertex_start: u32,
    vertex_count: u32,
};

pub const Instance = extern struct {
    transform: zalgebra.Mat4,
    normal_transform: [3]zalgebra.Vec3 align(16),
    color: zalgebra.Vec3 align(16),
    material: u64,
    mesh: u64,
};

pub const CameraData = extern struct {
    projection: zalgebra.Mat4,
    transform: zalgebra.Mat4,
    normal_transform: [3]zalgebra.Vec3 align(16),
};

pub const Scene = extern struct {
    camera: CameraData,
    instances: u64,
    meshes: u64,
    materials: u64,
    vertices: u64,
    normals: u64,
};
