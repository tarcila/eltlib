pub const core = @import("./core.zig");
pub const ecs = @import("./ecs.zig");

const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@This());
}
