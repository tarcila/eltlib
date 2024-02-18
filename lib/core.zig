//! eltlib core utilities.
pub const bits = @import("./core/bits.zig");
pub const string_utils = @import("./core/string_utils.zig");

const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@This());
}
