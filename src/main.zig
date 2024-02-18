const std = @import("std");
const core = @import("eltlib-core");
const sdl = @import("eltlib-sdl");
const zalgebra = @import("zalgebra");

const mach_objc = @import("mach-objc");
const ca = mach_objc.quartz_core.ca;
const mtl = mach_objc.metal.mtl;
const objc = mach_objc.objc;
const ns = mach_objc.foundation.ns;

const scene = @import("./scene//scene.zig");
const cube = @import("./scene/cube.zig");

pub fn main() !void {
    ns.init();
    ca.init();
    mtl.init();

    try sdl.setUp();
    defer sdl.tearDown();

    const window = try sdl.MainWindow.createWindow("SDL Metal Test", 640, 480);
    defer window.destroy();

    const device = window.device;

    // Shaders
    const src = @embedFile("./shaders/shape.metal");
    const srcstr = ns.String.stringWithUTF8String(src);

    var err: ?*ns.Error = null; // ns.Error.new();
    const shader_library = device.newLibraryWithSource_options_error(
        srcstr,
        null, // .{},
        &err,
    );
    if (shader_library == null) {
        const errstr = @as([*:0]const u8, @ptrCast(err.?.localizedDescription().cString().?));
        std.debug.print("failed with error: {s}\n", .{errstr});
        return;
    }
    const vertexfn = shader_library.?.newFunctionWithName(ns.String.stringWithUTF8String("vertexMain"));
    const fragmentfn = shader_library.?.newFunctionWithName(ns.String.stringWithUTF8String("fragmentMain"));

    // Scene
    const scene_vertices = cube.get_cube_vertices();
    const scene_normals = cube.get_cube_normals();
    const scene_uvs = cube.get_cube_uvs();
    const buffersize = @sizeOf(scene.Scene) + @sizeOf(scene.Instance) + @sizeOf(scene.Material) + @sizeOf(scene.Mesh) +
        @sizeOf(@TypeOf(scene_vertices)) + @sizeOf(@TypeOf(scene_normals)) + @sizeOf(@TypeOf(scene_uvs));

    const scenebuffer = device.newBufferWithLength_options(buffersize, mtl.ResourceStorageModeShared).?;
    const scenebufferslice = @as([*]u8, @ptrCast(scenebuffer.contents()))[0..buffersize];
    var fba = std.heap.FixedBufferAllocator.init(scenebufferslice);
    const allocator = fba.allocator();

    // system pointers
    const scene_data: *scene.Scene = @ptrCast(try allocator.alloc(scene.Scene, 1));
    const camera = &scene_data.camera;
    const instances = try allocator.alloc(scene.Instance, 1);
    const meshes = try allocator.alloc(scene.Mesh, 1);
    const materials = try allocator.alloc(scene.Material, 1);
    const vertices = try allocator.alloc([3]f32, scene_vertices.len);
    const normals = try allocator.alloc([3]f32, scene_normals.len);

    // related gpu adresses
    scene_data.instances = scenebuffer.gpuAddress() + (@intFromPtr(instances.ptr) - @intFromPtr(scene_data));
    scene_data.meshes = scenebuffer.gpuAddress() + (@intFromPtr(meshes.ptr) - @intFromPtr(scene_data));
    scene_data.materials = scenebuffer.gpuAddress() + (@intFromPtr(materials.ptr) - @intFromPtr(scene_data));
    scene_data.vertices = scenebuffer.gpuAddress() + (@intFromPtr(vertices.ptr) - @intFromPtr(scene_data));
    scene_data.normals = scenebuffer.gpuAddress() + (@intFromPtr(normals.ptr) - @intFromPtr(scene_data));

    camera.projection = zalgebra.Mat4.perspective(90, 1.0, 0.1, 100.0);
    camera.transform = zalgebra.Mat4.translate(zalgebra.Mat4.identity(), zalgebra.Vec3{ .data = .{ 0.0, 0.0, -4 } });
    camera.normal_transform[0] = zalgebra.Vec3.fromSlice(&.{ 1.0, 0.0, 0.0 });
    camera.normal_transform[1] = zalgebra.Vec3.fromSlice(&.{ 0.0, 1.0, 0.0 });
    camera.normal_transform[2] = zalgebra.Vec3.fromSlice(&.{ 0.0, 0.0, 1.0 });

    instances[0].color = zalgebra.Vec3.set(0.8);
    instances[0].transform = zalgebra.Mat4.identity();
    instances[0].normal_transform[0] = zalgebra.Vec3.fromSlice(&.{ 1.0, 0.0, 0.0 });
    instances[0].normal_transform[1] = zalgebra.Vec3.fromSlice(&.{ 0.0, 1.0, 0.0 });
    instances[0].normal_transform[2] = zalgebra.Vec3.fromSlice(&.{ 0.0, 0.0, 1.0 });
    instances[0].material = scene_data.materials;
    instances[0].mesh = scene_data.meshes;

    @memcpy(vertices, &scene_vertices);
    @memcpy(normals, &scene_normals);

    materials[0].name = scene.MaterialName.Phong;
    materials[0].descriptor.phong.diffuse_color = zalgebra.Vec3.set(0.8);

    meshes[0].vertex_start = 0;
    meshes[0].vertex_count = 36;

    std.debug.print("buffer {x}\n", .{scenebuffer.gpuAddress()});
    std.debug.print("scene_data {*}\n", .{scene_data});
    std.debug.print("instances {x}\n", .{scene_data.instances});
    std.debug.print("meshes {x}\n", .{scene_data.meshes});
    std.debug.print("materials {x}\n", .{scene_data.materials});
    std.debug.print("vertices {x}\n", .{scene_data.vertices});
    std.debug.print("normals {x}\n", .{scene_data.normals});

    // Pipeline
    const pipelinedesc: *mtl.RenderPipelineDescriptor = mtl.RenderPipelineDescriptor.alloc().init();
    pipelinedesc.setFragmentFunction(fragmentfn);
    pipelinedesc.setVertexFunction(vertexfn);

    const colorattachments = pipelinedesc.colorAttachments();
    const colorattachment0 = colorattachments.objectAtIndexedSubscript(0);
    colorattachment0.setPixelFormat(mtl.PixelFormatBGRA8Unorm);
    pipelinedesc.setDepthAttachmentPixelFormat(mtl.PixelFormatDepth16Unorm);

    const pso = device.newRenderPipelineStateWithDescriptor_error(pipelinedesc, &err);
    if (pso == null) {
        const errstr = @as([*:0]const u8, @ptrCast(err.?.localizedDescription().cString().?));
        std.debug.print("failed with error: {s}\n", .{errstr});
        return;
    }

    var time: f32 = 0.0;

    const depth_texture_desc = mtl.TextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        mtl.PixelFormatDepth16Unorm,
        @intFromFloat(window.metal_layer.drawableSize().width),
        @intFromFloat(window.metal_layer.drawableSize().height),
        false,
    );
    depth_texture_desc.setUsage(mtl.TextureUsageRenderTarget);
    depth_texture_desc.setStorageMode(mtl.StorageModeMemoryless);
    const depth_texture = device.newTextureWithDescriptor(depth_texture_desc);

    const depth_stencil_desc: *mtl.DepthStencilDescriptor = mtl.DepthStencilDescriptor.alloc().init();
    depth_stencil_desc.setDepthCompareFunction(mtl.CompareFunctionLess);
    depth_stencil_desc.setDepthWriteEnabled(true);
    const depth_stencil_state = device.newDepthStencilStateWithDescriptor(depth_stencil_desc);

    // Argument buffer
    const argument_descriptor: *mtl.ArgumentDescriptor = mtl.ArgumentDescriptor.alloc().init();
    argument_descriptor.setIndex(0);
    argument_descriptor.setDataType(mtl.DataTypePointer);
    argument_descriptor.setAccess(mtl.ArgumentAccessReadOnly);
    // const array = ns.Array(*mtl.ArgumentDescriptor).array(); //WithObject(&argument_descriptor);
    var objects = [_]*mtl.ArgumentDescriptor{argument_descriptor};
    const array = ns.Array(*mtl.ArgumentDescriptor).arrayWithObjects_count(@ptrCast(&objects), objects.len);
    const argument_encoder = device.newArgumentEncoderWithArguments(array).?;

    const argumentbuffer = device.newBufferWithLength_options(argument_encoder.encodedLength(), mtl.ResourceStorageModeShared);
    argument_encoder.setArgumentBuffer_offset(argumentbuffer, 0);
    argument_encoder.setBuffer_offset_atIndex(scenebuffer, 0, 0);

    while (true) {
        if (sdl.pollEvent()) |event| {
            switch (event) {
                .QUIT => break,
            }
        }

        const pool = objc.autoreleasePoolPush();
        defer objc.autoreleasePoolPop(pool);

        const surface = window.metal_layer.nextDrawable().?;
        const red = time - @floor(time);
        time += 0.01;
        const clearColor = mtl.ClearColor.init(red, 0, 0, 1);

        const r = @mod(time * 50, 360);
        instances[0].transform = zalgebra.Mat4.mul(
            zalgebra.Mat4.fromRotation(r, zalgebra.Vec3.up()),
            zalgebra.Mat4.fromRotation(-r, zalgebra.Vec3.forward()),
        );
        const normal_rot = zalgebra.Mat4.mul(
            zalgebra.Mat4.fromRotation(r, zalgebra.Vec3.up()),
            zalgebra.Mat4.fromRotation(-r, zalgebra.Vec3.forward()),
        );
        for (0..3) |i| instances[0].normal_transform[i] = zalgebra.Vec3.fromSlice(&normal_rot.data[i]);

        const renderPassDescriptor = mtl.RenderPassDescriptor.renderPassDescriptor();
        const colorAttachments = renderPassDescriptor.colorAttachments();
        const colorAttachment0 = colorAttachments.objectAtIndexedSubscript(0);
        colorAttachment0.setClearColor(clearColor);
        colorAttachment0.setLoadAction(mtl.LoadActionClear);
        colorAttachment0.setStoreAction(mtl.StoreActionStore);
        colorAttachment0.setTexture(surface.texture());
        const depthAttachment = renderPassDescriptor.depthAttachment();
        depthAttachment.setClearDepth(1);
        depthAttachment.setTexture(depth_texture);

        const buffer = window.queue.commandBuffer().?;

        const encoder = buffer.renderCommandEncoderWithDescriptor(renderPassDescriptor).?;
        encoder.setDepthStencilState(depth_stencil_state);

        encoder.setCullMode(mtl.CullModeBack);

        encoder.useResource_usage(@ptrCast(scenebuffer), mtl.ResourceUsageRead);
        encoder.setVertexBuffer_offset_atIndex(argumentbuffer, 0, 0);
        encoder.setRenderPipelineState(pso.?);
        encoder.drawPrimitives_vertexStart_vertexCount(mtl.PrimitiveTypeTriangle, 0, 12 * 3);

        encoder.endEncoding();

        buffer.presentDrawable(@ptrCast(surface));
        buffer.commit();
    }
}

test {}
