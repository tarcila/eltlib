const System = @import("./system.zig");

pub fn getSystem(comptime system: type) System {
    _ = system; // autofix

}
