const std = @import("std");

alive: bool,
id: u64,

pub const invalid_id = std.math.maxInt(@TypeOf(@This().id));

pub fn addComponent() !void {}

pub fn removeComponent() !void {}
