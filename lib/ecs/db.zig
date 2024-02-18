// DB
// entity: an index into a mapping table (more below)
// signatures: computed from components on an entity (~archetype)
// component storage: group components of entities per signature
//
// For instance, with two components A and B, over entities e1, e2, e3 that could give:
// 0: e1(A)
// 1: e2(A, B)
// 3: e3(B)
// 3 possible signatures, A, B and AB
// For A we would have:
// 0 x x
// For B we would have:
// x x 0
// For AB we would have:
// x 0 x
// Where x means empty, 0 means that index 0 in the related components array maps to the corresponding entity given its index
// More efficient component storage can be handled using bucketing
// Add and removing a component over an entity implies some balancing
// => if an entity is added/removed a component, it needs to be removed from its current group (signature based) and added to
//   another (possibly new) group.
//   This can imply filling holes in the target group if any, or appending, or even creating a new bucket.
//   In the group of origin, the entity needs to be marked as dead. This can usually easily be done swap the now dead slot
//   with the last valid value, and this would imply moving data. But moving data is already implied by the fact that
//   data need to be moved from one signature group to another, that's just adding a bit more.
//   Note that larger data are probably expected to be pointers, so should be lightweight enough to move.
// Iteration, one needs to try and ensure that adding/removing components during iteration does not invalidate the current
//     iteration. Not sure if this can be fully handled nor if that actually makes sense.

// First challenge would to efficient compute a component idx for the signature. comptime seems to be doable and is the most
// efficient. But some components are most probably expected to be runtime based (based off a string?) and would need
// to be register at runtime. To be confirmed if this is actually useful.
//

// Handle Tags as empty components/struct.

const std = @import("std");
const components = @import("./components.zig");

pub const ComponentError = error{
    InvalidComponent,
};

pub const EntityError = error{
    InvalidEntity,
};

pub const Settings = struct {
    reserve: usize = 16,
    bucket_size: usize = 64, // unused yet
};

pub fn Db(comptime EnabledComponentTypes: []const type, comptime settings: Settings) type {
    return struct {
        pub usingnamespace components.ComponentSet(EnabledComponentTypes);

        const Self = @This();

        const EnabledComponents = EnabledComponentTypes;

        pub const EntityId = struct {
            index: usize,
        };

        const Bucket = struct {
            signature: Self.ComponentsSignature,
            bitmap: std.DynamicBitSetUnmanaged,
            soa: *anyopaque,
            release_soa: *const fn (allocator: std.mem.Allocator, soa: *anyopaque) void,
            get_soa_pointers: *const fn (soa: *anyopaque, mask: Self.ComponentsSignature, ptrs: [][*]u8) void,

            fn PointersFromTypes(comptime Types: []const type) []type {
                var Pointers: [Types.len]type = undefined;
                for (Types, 0..) |T, i| {
                    Pointers[i] = [*]T;
                }

                return &Pointers;
            }

            fn SinglePointersFromTypes(comptime Types: []const type) []type {
                var Pointers: [Types.len]type = undefined;
                for (Types, 0..) |T, i| {
                    Pointers[i] = *T;
                }

                return &Pointers;
            }

            fn Slice(comptime Components: []const type) type {
                return @Type(@typeInfo(std.meta.Tuple(PointersFromTypes(Components))));
            }

            fn Item(comptime Components: []const type) type {
                // return @Type(@typeInfo(
                return std.meta.Tuple(SinglePointersFromTypes(Components)); //));
            }

            fn slice(self: Bucket, comptime Components: []const type) !Slice(Components) {
                const components_signature = try Self.getComponentsSignature(Components);
                if ((components_signature & ~self.signature) != 0) {
                    return ComponentError.InvalidComponent;
                }
                var u8pointers: [Components.len][*]u8 = undefined;
                self.get_soa_pointers(self.soa, components_signature, &u8pointers);

                var result: Slice(Components) = undefined;
                inline for (Components, 0..) |Component, i| {
                    const component_index = try Self.getComponentIndex(Component);
                    const component_before_mask = std.math.shl(Self.ComponentsSignature, 1, component_index) - 1;
                    const source_index = @popCount(self.signature & component_before_mask);
                    result[i] = @ptrCast(@alignCast(u8pointers[source_index]));
                }

                return result;
            }

            fn item(self: Bucket, comptime Components: []const type, item_index: usize) !Item(Components) {
                const slices = try self.slice(Components);
                var result: Item(Components) = undefined;

                inline for (slices, 0..) |ptr, i| {
                    result[i] = &ptr[item_index];
                }

                return result;
            }

            fn init(allocator: std.mem.Allocator, comptime Components: []const type) !Bucket {
                const ComponentsTuple = std.meta.Tuple(Components);
                const soa = try allocator.create(std.MultiArrayList(ComponentsTuple));
                soa.* = .{};
                try soa.resize(allocator, settings.bucket_size);
                const bitmap = try std.DynamicBitSetUnmanaged.initFull(allocator, settings.bucket_size);
                const VTable = struct {
                    fn release_soa(allocator_: std.mem.Allocator, soa_: *anyopaque) void {
                        const mal = @as(*std.MultiArrayList(std.meta.Tuple(Components)), @alignCast(@ptrCast(soa_)));
                        mal.deinit(allocator_);
                        allocator_.destroy(mal);
                    }
                    fn get_soa_pointers(soa_: *anyopaque, mask: Self.ComponentsSignature, ptrs: [][*]u8) void {
                        std.debug.assert(@popCount(mask) == ptrs.len);
                        const bucket_signature = try Self.getComponentsSignature(Components);
                        const mal = @as(*std.MultiArrayList(std.meta.Tuple(Components)), @alignCast(@ptrCast(soa_)));
                        const sl = mal.slice();

                        inline for (Components) |Component| {
                            const component_index = try Self.getComponentIndex(Component);
                            const component_mask = std.math.shl(Self.ComponentsSignature, 1, component_index);
                            if (component_mask & mask != 0) {
                                const component_before_mask = component_mask - 1;
                                const source_index = @popCount(bucket_signature & component_before_mask);
                                const target_index = @popCount(mask & component_before_mask);

                                ptrs[target_index] = @ptrCast(@alignCast(sl.ptrs[source_index]));
                            }
                        }
                    }
                };

                return .{
                    .signature = try Self.getComponentsSignature(Components),
                    .bitmap = bitmap,
                    .soa = soa,
                    .release_soa = VTable.release_soa,
                    .get_soa_pointers = VTable.get_soa_pointers,
                };
            }

            fn deinit(self: *Bucket, allocator: std.mem.Allocator) void {
                self.release_soa(allocator, self.soa);
                self.bitmap.deinit(allocator);
            }
        };

        allocator: std.mem.Allocator,
        // Entities
        bitmap: std.DynamicBitSetUnmanaged,
        signatures: std.ArrayListUnmanaged(Self.ComponentsSignature),
        // Map to components
        indices_in_buckets: std.ArrayListUnmanaged(usize),
        buckets: std.AutoArrayHashMapUnmanaged(Self.ComponentsSignature, Bucket),

        // Init empty Db
        pub fn init(allocator: std.mem.Allocator) !Self {
            var signatures: std.ArrayListUnmanaged(Self.ComponentsSignature) = .{};
            try signatures.resize(allocator, settings.reserve);

            var indices_in_buckets: std.ArrayListUnmanaged(usize) = .{};
            try indices_in_buckets.resize(allocator, settings.reserve);

            return Self{
                .allocator = allocator,
                .bitmap = try std.DynamicBitSetUnmanaged.initFull(allocator, settings.reserve),
                .signatures = signatures,
                .indices_in_buckets = indices_in_buckets,
                .buckets = try std.AutoArrayHashMapUnmanaged(Self.ComponentsSignature, Bucket).init(allocator, &.{}, &.{}),
            };
        }

        /// Release the Db.
        pub fn deinit(self: *Self) void {
            for (self.buckets.values()) |*bucket| {
                bucket.deinit(self.allocator);
                //value.bitmap.deinit(self.allocator);
                //FIXME: How to get access to the right MultiArrayUna
            }
            self.buckets.deinit(self.allocator);
            self.indices_in_buckets.deinit(self.allocator);
            self.signatures.deinit(self.allocator);
            self.bitmap.deinit(self.allocator);
        }

        /// Allocate an index for a new entity
        fn allocateEntityIndex(self: *Self) !usize {
            const maybepos = self.bitmap.toggleFirstSet();
            if (maybepos) |pos| {
                // Already sized correctly
                return pos;
            } else {
                // No free items, need to allocate
                const pos = self.bitmap.capacity();
                const new_len = pos * 2;
                try self.bitmap.resize(self.allocator, new_len, true);
                try self.indices_in_buckets.resize(self.allocator, new_len);
                try self.signatures.resize(self.allocator, new_len);
                self.bitmap.toggle(pos);

                return pos;
            }
        }

        /// Release the index used by an entity.
        fn releaseEntityIndex(self: *Self, entity_index: usize) void {
            std.debug.assert(entity_index < self.bitmap.bit_length);
            std.debug.assert(self.bitmap.isSet(entity_index));

            self.bitmap.set(entity_index);
        }

        // Add a new entity given the provided components
        pub fn addEntity(self: *Self, comptime Components: []const type) !EntityId {
            const entity_index = try self.allocateEntityIndex();
            const components_signature = try Self.getComponentsSignature(Components);

            const bucket = try self.buckets.getOrPut(self.allocator, components_signature);
            if (!bucket.found_existing) {
                bucket.value_ptr.* = try Bucket.init(self.allocator, Components);
            }

            // Find first free slot, resize if necessary and fill in the multiarraylist
            // FIXME: Allocate entity in bucket, get bucket position and store it
            // in indices_in_buckets
            // Move bucket related code to buckets.zig#Bucket
            const maybepos = bucket.value_ptr.bitmap.toggleFirstSet();
            if (maybepos) |pos| {
                self.indices_in_buckets.items[entity_index] = pos;
            } else {
                const pos = self.bitmap.capacity();
                const new_len = pos * 2;
                try bucket.value_ptr.bitmap.resize(self.allocator, new_len, true);
                const soa = @as(*std.MultiArrayList(std.meta.Tuple(Components)), @alignCast(@ptrCast(bucket.value_ptr.soa)));
                try soa.resize(self.allocator, new_len);
                self.indices_in_buckets.items[entity_index] = pos;
            }
            self.signatures.items[entity_index] = components_signature;

            return .{ .index = entity_index };
        }

        // Remove an entity, freeing its associated component store.
        pub fn removeEntity(self: *Self, entity_id: EntityId) !void {
            self.releaseEntityIndex(entity_id.index);
        }

        pub fn item(self: Self, comptime Components: []const type, item_index: usize) !Bucket.Item(Components) {
            std.debug.assert(!self.bitmap.isSet(item_index));
            const signature = self.signatures.items[item_index];
            const bucket = self.buckets.get(signature).?;
            const bucket_index = self.indices_in_buckets.items[item_index];

            return bucket.item(Components, bucket_index);
        }
    };
}

// Testing
const Velocity = struct {
    v: [3]f32,
};
const Position = struct {
    p: [3]f32,
};
const Weight = struct {
    f: f32,
};

const Velocity2 = struct { [3]f32 };
const Position2 = struct { [3]f32 };

const UserCreated = struct {};
const AutoCreated = struct {};

const MyDb = Db(&.{
    // Components
    Position,
    Velocity,
    Weight,
    Position2,
    Velocity2,
    // Tags
    UserCreated,
    AutoCreated,
}, .{});

test "db.getComponentIndex" {
    try std.testing.expectEqual(0, MyDb.getComponentIndex(Position));
    try std.testing.expectEqual(1, MyDb.getComponentIndex(Velocity));
    try std.testing.expectEqual(2, MyDb.getComponentIndex(Weight));

    try std.testing.expectError(ComponentError.InvalidComponent, MyDb.getComponentIndex(f32));
}

test "db.getComponentsSignature" {
    try std.testing.expectEqual(1, MyDb.getComponentsSignature(&.{Position}));
    try std.testing.expectEqual(2, MyDb.getComponentsSignature(&.{Velocity}));
    try std.testing.expectEqual(4, MyDb.getComponentsSignature(&.{Weight}));

    try std.testing.expectEqual(7, MyDb.getComponentsSignature(&.{ Position, Velocity, Weight }));
    try std.testing.expectError(ComponentError.InvalidComponent, MyDb.getComponentsSignature(&.{f32}));
}

test "db.addEntity" {
    var db = try MyDb.init(std.testing.allocator);
    defer db.deinit();
    const entity = try db.addEntity(&.{ Velocity, Velocity2 });

    // Get the components of a specific item
    const item = try db.item(&.{Velocity}, entity.index);
    item[0].v = .{ 0, 1, 2 };

    // Iterate over items with those components
    //const items = try .db.iterItems(&.{Velocity});
    // Iterate over buckets holding components with those items
    //const buckets = try db.iterBuckets(&.{Velocity});

    // db.addComponentToEntity(entity, &.{UserCreated});
    // const entity_components = db.getEntityComponents(entity, struct {
    //     position: Position,
    //     velocity: Velocity,
    // });
    std.debug.print("\n\n{any}\n", .{entity});
    std.debug.print("\n\n{any}\n", .{db.buckets});
    std.debug.print("\n\n{any}\n", .{item});
}
