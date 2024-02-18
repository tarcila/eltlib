//! eltlib ecs utilities.
pub const buckets = @import("./ecs/buckets.zig");

const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@This());
}
