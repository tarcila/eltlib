const std = @import("std");

pub const ComponentError = error{
    DuplicatedComponent,
    InvalidComponent,
};

pub fn ComponentsSet(comptime ComponentsInSet: []const type) type {
    if (ComponentsInSet.len == 0) {
        @compileError("ComponentsInSet needs to have a least one type");
    }

    inline for (ComponentsInSet, 0..) |C, i| {
        inline for (ComponentsInSet, 0..) |OtherC, other_i| {
            if (C == OtherC and i != other_i) {
                @compileError("Component types in ComponentsInSet must be unique. '" ++ @typeName(C) ++ "' is a duplicate.");
            }
        }
    }

    return struct {
        /// The type of the index of a component, if an actual store is needed.
        pub const ComponentIndex = @Type(.{
            .Int = .{
                .signedness = std.builtin.Signedness.unsigned,
                .bits = std.math.log2_int_ceil(u16, ComponentsInSet.len),
            },
        });

        /// The signature of a set of components.
        pub const ComponentsSignature = @Type(.{
            .Int = .{
                .signedness = std.builtin.Signedness.unsigned,
                .bits = ComponentsInSet.len,
            },
        });

        /// The components this set holds
        pub const Components = ComponentsInSet;

        /// Compute component identifier
        pub fn getComponentIndex(comptime C: type) !comptime_int {
            inline for (Components, 0..) |c, i| {
                if (C == c) return i;
            }

            return ComponentError.InvalidComponent;
        }

        /// Compute the identifer of a set of components
        pub fn getComponentsSignature(comptime Cs: []const type) !comptime_int {
            var sig = 0;
            inline for (Cs) |C| {
                const index = 1 << try getComponentIndex(C);
                sig = sig | index;
            }

            return sig;
        }
    };
}

test "Component Indexing" {
    const C1 = struct { f32 };
    const C2 = struct { f32 };
    const C3 = struct { f32 };

    const Components = ComponentsSet(&.{ C1, C2, C3 });

    try std.testing.expectEqual(2, @typeInfo(Components.ComponentIndex).Int.bits);

    try std.testing.expectEqual(0, Components.getComponentIndex(C1));
    try std.testing.expectEqual(1, Components.getComponentIndex(C2));
    try std.testing.expectEqual(2, Components.getComponentIndex(C3));

    try std.testing.expectEqual(ComponentError.InvalidComponent, Components.getComponentIndex(u32));
}

test "Components Signature" {
    const C1 = struct { f32 };
    const C2 = struct { f32 };
    const C3 = struct { f32 };

    const Components = ComponentsSet(&.{ C1, C2, C3 });

    try std.testing.expectEqual(3, @typeInfo(Components.ComponentsSignature).Int.bits);
    try std.testing.expectEqual(1, @sizeOf(Components.ComponentsSignature));

    try std.testing.expectEqual(1, Components.getComponentsSignature(&.{C1}));
    try std.testing.expectEqual(2, Components.getComponentsSignature(&.{C2}));
    try std.testing.expectEqual(4, Components.getComponentsSignature(&.{C3}));

    try std.testing.expectEqual(3, Components.getComponentsSignature(&.{ C1, C2 }));
    try std.testing.expectEqual(5, Components.getComponentsSignature(&.{ C1, C3 }));
    try std.testing.expectEqual(6, Components.getComponentsSignature(&.{ C2, C3 }));
    try std.testing.expectEqual(7, Components.getComponentsSignature(&.{ C1, C2, C3 }));
}
