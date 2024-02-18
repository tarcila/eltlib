const std = @import("std");
const mtl = @import("mach-objc").metal.mtl;

allocator: *std.mem.Allocator,
device: *mtl.Device,

const ResourceManager = @This();

const Buffer = struct {};

pub fn init(allocator: std.mem.Allocator, device: mtl.Device) !ResourceManager {
    return ResourceManager{
        .allocator = allocator,
        .device = device,
    };
}

pub fn allocateBuffer(self: ResourceManager, len: usize) !Buffer {
    self.device.newBufferWithLength_options(len, mtl.ResourceCPUCacheModeDefaultCache);
}
