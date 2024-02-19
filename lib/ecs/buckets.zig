//! Bucketing and bitmap based allocation for a given set of components
const std = @import("std");
const bits = @import("../lib.zig").core.bits;

const components = @import("./components.zig");

pub const BucketError = error{
    OutOfSpace,
};

/// Returns a tuple of slices to the given components
fn Slice(comptime Components: []const type) type {
    var Pointers: [Components.len]type = undefined;
    for (Components, 0..) |T, i| {
        Pointers[i] = []T;
    }

    return std.meta.Tuple(&Pointers);
}

/// Returns a tuple of single-pointers to the given components
fn Item(comptime Components: []const type) type {
    var Pointers: [Components.len]type = undefined;
    for (Components, 0..) |T, i| {
        Pointers[i] = *T;
    }

    return std.meta.Tuple(&Pointers);
}

/// Compile time check that SubSet is effectively included in SuperSet
fn checkComponents(comptime SuperSet: []const type, comptime SubSet: []const type) void {
    inline for (SubSet) |C| {
        inline for (SuperSet) |OtherC| {
            if (C == OtherC) {
                break;
            }
        } else {
            @compileError("Buckets components must be a subset of ComponentsInDb. " ++ @typeName(C) ++ " is missing from " ++ @typeName(std.meta.Tuple(SuperSet)) ++ ".");
        }
    }
}

/// Settings for compile time bucket configuration
pub const BucketSettings = struct {
    bucket_size: usize = 32,
};

/// A Bucket able to hold the given components
pub fn Bucket(comptime ComponentsInBucket: []const type, comptime settings: BucketSettings) type {
    if (ComponentsInBucket.len == 0) {
        @compileError("ComponentsInSet needs to have a least one type");
    }

    inline for (ComponentsInBucket, 0..) |C, i| {
        inline for (ComponentsInBucket, 0..) |OtherC, other_i| {
            if (C == OtherC and i != other_i) {
                @compileError("Component types in ComponentsInSet must be unique. '" ++ @typeName(C) ++ "' is a duplicate.");
            }
        }
    }

    return struct {
        usingnamespace components.ComponentsSet(ComponentsInBucket);
        const ComponentsInBucketAsTuple = std.meta.Tuple(ComponentsInBucket);

        bitmap: std.StaticBitSet(settings.bucket_size) = std.StaticBitSet(settings.bucket_size).initFull(),
        mal: std.MultiArrayList(ComponentsInBucketAsTuple) = .{},

        /// Returns a many-pointer accessor to the given components.
        /// Components must be a subset of Buckets components.
        pub fn slice(self: @This(), comptime Components: []const type) Slice(Components) {
            checkComponents(ComponentsInBucket, Components);
            const soa_slice = self.mal.slice();
            var slices: Slice(Components) = undefined;
            inline for (Components, &slices) |Component, *sl| {
                const component_index = @This().getComponentIndex(Component) catch unreachable;
                const ptr = @as([*]Component, @ptrCast(@alignCast(soa_slice.ptrs[component_index])));
                sl.* = ptr[0..settings.bucket_size];
            }

            return slices;
        }

        /// Returns a single-pointer accessor to the given components.
        /// Components must be a subset of Buckets components.
        pub fn item(self: @This(), comptime Components: []const type, index: usize) Item(Components) {
            checkComponents(ComponentsInBucket, Components);
            const slices = self.slice(Components);
            var ptrs: Item(Components) = undefined;

            inline for (slices, &ptrs) |sl, *ptr| {
                ptr.* = &sl[index];
            }

            return ptrs;
        }

        /// Initialize a bucket using the given allocator.
        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .bitmap = std.StaticBitSet(settings.bucket_size).initFull(),
                .mal = blk: {
                    var mal: std.MultiArrayList(ComponentsInBucketAsTuple) = .{};
                    try mal.resize(allocator, settings.bucket_size);
                    break :blk mal;
                },
            };
        }

        /// Release resources used by this allocator.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.mal.deinit(allocator);
            self.bitmap = std.StaticBitSet(settings.bucket_size).initEmpty();
        }

        /// Try and allocate a slot for one item.
        /// Returns the item index in case of success.
        pub fn allocateItem(self: *@This()) !usize {
            return self.bitmap.toggleFirstSet() orelse BucketError.OutOfSpace;
        }

        /// Release the item at the given index.
        pub fn releaseItem(self: *@This(), entry: usize) void {
            std.debug.assert(!self.bitmap.isSet(entry));
            self.bitmap.toggle(entry);
        }

        /// Try and allocate consecutive slots for `count` items.
        /// Return the index of the first item in case of success.
        pub fn allocateItems(self: *@This(), count: usize) !usize {
            const maybe_range = bits.findShortestBitsSetSequenceAtLeast(self.bitmap.mask, count);
            if (maybe_range) |range| {
                self.bitmap.setRangeValue(.{ .start = range.start, .end = range.start + range.len }, false);
                return range.start;
            }
            return BucketError.OutOfSpace;
        }

        /// Release `count` items starting at `start` index.
        pub fn releaseItems(self: *@This(), start: usize, count: usize) void {
            std.debug.assert(blk: {
                var mask = std.StaticBitSet(settings.bucket_size).initEmpty();
                mask.setRangeValue(.{ .start = start, .end = start + count }, true);
                mask.setIntersection(self.bitmap);
                break :blk (mask.mask == 0);
            });

            self.bitmap.setValueRange(start, start + count, true);
        }
    };
}

test "Bucket.Allocate" {
    const bucket_size = 32;
    const C1 = struct { i32 };
    const C2 = struct { i32 };
    const C3 = struct { i32 };

    var bucket = try Bucket(&.{ C1, C2, C3 }, .{ .bucket_size = bucket_size }).init(std.testing.allocator);
    defer bucket.deinit(std.testing.allocator);

    // Try allocating 10 consecutive items.
    for (0..10) |i| {
        try std.testing.expectEqual(i, bucket.allocateItem());
    }
    // Free even indices.
    for (0..5) |i| bucket.releaseItem(i * 2);

    // And try reallocating.
    for (0..5) |i| {
        try std.testing.expectEqual(i * 2, bucket.allocateItem());
    }

    // Allocate the rest of the items.
    for (10..bucket_size) |i| {
        try std.testing.expectEqual(i, bucket.allocateItem());
    }

    // Next allocation should fail.
    try std.testing.expectEqual(BucketError.OutOfSpace, bucket.allocateItem());

    // Free a few entry midway.
    for (10..15) |i| bucket.releaseItem(i);

    // Try and allocate a range that does not fit.
    try std.testing.expectEqual(BucketError.OutOfSpace, bucket.allocateItems(6));

    // Try and allocate a range that fits.
    try std.testing.expectEqual(10, bucket.allocateItems(5));

    // Next allocation should fail.
    try std.testing.expectEqual(BucketError.OutOfSpace, bucket.allocateItem());
}

test "Bucket.Access" {
    const bucket_size = 32;
    const C1 = struct { i32 };
    const C2 = struct { i32 };
    const C3 = struct { i32 };

    var bucket = try Bucket(&.{ C1, C2, C3 }, .{ .bucket_size = bucket_size }).init(std.testing.allocator);
    defer bucket.deinit(std.testing.allocator);

    // Set values for all the items
    for (0..bucket_size) |i| {
        const idx = bucket.allocateItem() catch unreachable;
        const item = bucket.item(&.{ C1, C2, C3 }, idx);
        const v = @as(i32, @intCast(i + 1));
        item[0].* = .{v};
        item[1].* = .{v * 100};
        item[2].* = .{v * 10000};
    }

    // Verify the values in the underlying MultiArrayList
    for (0..bucket_size) |i| {
        const item = bucket.mal.get(i);
        const v = @as(i32, @intCast(i + 1));
        try std.testing.expectEqual(.{v}, item[0]);
        try std.testing.expectEqual(.{v * 100}, item[1]);
        try std.testing.expectEqual(.{v * 10000}, item[2]);
    }

    // Try and do the same with a slice accessor
    const slice = bucket.slice(&.{ C1, C2, C3 });
    for (slice[0], slice[1], slice[2], 0..) |*c1, *c2, *c3, i| {
        const v = @as(i32, @intCast(i + 1));
        c1.* = .{v * -1};
        c2.* = .{v * -100};
        c3.* = .{v * -10000};
    }

    // Verify the values in the underlying MultiArrayList
    for (0..bucket_size) |i| {
        const item = bucket.mal.get(i);
        const v = @as(i32, @intCast(i + 1));
        try std.testing.expectEqual(.{v * -1}, item[0]);
        try std.testing.expectEqual(.{v * -100}, item[1]);
        try std.testing.expectEqual(.{v * -10000}, item[2]);
    }
}

pub const DbBucketSettings = struct {
    bucket_size: usize = 32,
    reserve: usize = 1,
};

pub fn DbBucket(comptime ComponentsInDb: []const type, comptime settings: DbBucketSettings) type {
    return struct {
        const ComponentsDb = components.ComponentsSet(ComponentsInDb);
        const UntypedBucket = Bucket(ComponentsInDb, .{ .bucket_size = settings.bucket_size });

        do_deinit: *const fn (dbbucket: *@This(), allocator: std.mem.Allocator) void,
        do_slice: *const fn (dbbucket: @This(), signature: ComponentsDb.ComponentsSignature, bucket_index: usize, ptrs: [][*]u8) components.ComponentError![][*]u8,
        do_addOneBucket: *const fn (dbbucket: *@This(), allocator: std.mem.Allocator) std.mem.Allocator.Error!*UntypedBucket,
        do_promote: *const fn (dbbucket: *@This(), allocator: std.mem.Allocator, entry: usize) std.mem.Allocator.Error!void,
        do_demote: *const fn (dbbucket: *@This(), allocator: std.mem.Allocator, entry: usize) void,

        buckets: std.ArrayListUnmanaged(UntypedBucket),
        signature: ComponentsDb.ComponentsSignature,

        pub fn init(allocator: std.mem.Allocator, comptime ComponentsInBucket: []const type) !@This() {
            _ = allocator; // autofix
            checkComponents(ComponentsInDb, ComponentsInBucket);

            const ComponentsBucket = components.ComponentsSet(ComponentsInBucket);
            const TypedBucket = Bucket(ComponentsInBucket, .{ .bucket_size = settings.bucket_size });
            const TypedBucketList = std.ArrayListUnmanaged(TypedBucket);

            const Outter = @This();

            const vtable = struct {
                fn deinit(dbbucket: *Outter, allocator_: std.mem.Allocator) void {
                    const buckets: *TypedBucketList = @ptrCast(@alignCast(&dbbucket.buckets));
                    for (buckets.items) |*bucket| {
                        bucket.deinit(allocator_);
                    }
                    buckets.deinit(allocator_);
                }

                fn slice(dbbucket: Outter, signature: ComponentsDb.ComponentsSignature, bucket_index: usize, ptrs: [][*]u8) components.ComponentError![][*]u8 {
                    if ((signature & ~dbbucket.signature) != 0) {
                        return components.ComponentError.InvalidComponent;
                    }
                    std.debug.assert(@popCount(signature) == ptrs.len);

                    const buckets: *const TypedBucketList = @ptrCast(@alignCast(&dbbucket.buckets));
                    std.debug.assert(bucket_index < buckets.items.len);
                    const bucket = buckets.items[bucket_index];
                    const typed_ptrs = bucket.slice(ComponentsInBucket);

                    inline for (ComponentsInBucket) |C| {
                        const source_index = try ComponentsBucket.getComponentIndex(C);
                        const db_index = try ComponentsDb.getComponentIndex(C);
                        const db_component_mask = std.math.shl(ComponentsDb.ComponentsSignature, 1, db_index);
                        if (db_component_mask & signature != 0) {
                            const component_before_mask = db_component_mask - 1;
                            const target_index = @popCount(signature & component_before_mask);
                            ptrs[target_index] = @ptrCast(@alignCast(typed_ptrs[source_index]));
                        }
                    }

                    return ptrs[0..@popCount(signature)];
                }

                fn addOneBucket(dbbucket: *Outter, allocator_: std.mem.Allocator) std.mem.Allocator.Error!*UntypedBucket {
                    const buckets: *TypedBucketList = @ptrCast(@alignCast(&dbbucket.buckets));
                    const new_entry = try buckets.addOne(allocator_);
                    new_entry.* = .{};
                    return @ptrCast(new_entry);
                }

                fn promoteBucket(dbbucket: *Outter, allocator_: std.mem.Allocator, entry: usize) std.mem.Allocator.Error!void {
                    const buckets: *const TypedBucketList = @ptrCast(@alignCast(&dbbucket.buckets));
                    buckets.items[entry] = try TypedBucket.init(allocator_);
                }

                fn demoteBucket(dbbucket: *Outter, allocator_: std.mem.Allocator, entry: usize) void {
                    const buckets: *const TypedBucketList = @ptrCast(@alignCast(&dbbucket.buckets));
                    buckets.items[entry].deinit(allocator_);
                }
            };

            return comptime blk: {
                const this = @This(){
                    .do_deinit = vtable.deinit,
                    .do_slice = vtable.slice,
                    .do_addOneBucket = vtable.addOneBucket,
                    .do_promote = vtable.promoteBucket,
                    .do_demote = vtable.demoteBucket,
                    .buckets = .{},
                    .signature = try ComponentsDb.getComponentsSignature(ComponentsInBucket),
                };

                std.debug.assert(@sizeOf(TypedBucketList) == @sizeOf(@TypeOf(@field(this, "buckets"))));

                break :blk this;
            };
        }

        fn slice(self: @This(), comptime Components: []const type, bucket_index: usize) !Slice(Components) {
            const signature = try ComponentsDb.getComponentsSignature(Components);
            var u8_ptrs: [Components.len][*]u8 = undefined;
            _ = try self.do_slice(self, signature, bucket_index, &u8_ptrs);

            var cs: Slice(Components) = undefined;
            inline for (Components, 0..) |Component, target_index| {
                const db_index = try ComponentsDb.getComponentIndex(Component);
                const db_component_mask = std.math.shl(ComponentsDb.ComponentsSignature, 1, db_index);

                const component_before_mask = db_component_mask - 1;
                const source_index = @popCount(signature & component_before_mask);
                const ptr = @as([*]Component, @ptrCast(@alignCast(u8_ptrs[source_index])));
                cs[target_index] = ptr[0..settings.bucket_size];
            }

            return cs;
        }

        fn SliceIterator(comptime Components: []const type) type {
            const Outter = @This();

            return struct {
                dbbucket: Outter,
                bucket_index: usize,

                pub fn next(self: *@This()) ?Slice(Components) {
                    while (self.bucket_index < self.dbbucket.buckets.items.len) {
                        std.debug.print("{any} == {}\n", .{
                            self.dbbucket.buckets.items[self.bucket_index].bitmap,
                            ~@as(@TypeOf(self.dbbucket.buckets.items[self.bucket_index].bitmap).MaskInt, 0),
                        });
                        const index = self.bucket_index;
                        self.bucket_index += 1;

                        if (self.dbbucket.buckets.items[index].bitmap.mask == ~@as(@TypeOf(self.dbbucket.buckets.items[self.bucket_index].bitmap).MaskInt, 0)) continue;
                        return self.dbbucket.slice(Components, index) catch unreachable;
                    } else return null;
                }
            };
        }

        pub fn sliceIterator(self: @This(), comptime Components: []const type) !SliceIterator(Components) {
            if (try ComponentsDb.getComponentsSignature(Components) & ~self.signature != 0) return components.ComponentError.InvalidComponent;

            return .{
                .dbbucket = self,
                .bucket_index = 0,
            };
        }

        pub fn allocateItem(self: *@This(), allocator_: std.mem.Allocator) std.mem.Allocator.Error!usize {
            var targetbucket: *UntypedBucket = undefined;
            var targetbucketindex: usize = 0;

            for (self.buckets.items, 0..) |*bucket, index| {
                if (bucket.bitmap.mask != 0) {
                    targetbucket = bucket;
                    targetbucketindex = index;
                    break;
                }
            } else {
                targetbucketindex = self.buckets.items.len;
                targetbucket = @ptrCast(try self.do_addOneBucket(self, allocator_));
            }

            return settings.bucket_size * targetbucketindex + targetbucket.bitmap.toggleFirstSet().?;
        }

        pub fn allocateItems(self: *@This(), allocator_: std.mem.Allocator, item_count: usize) std.mem.Allocator.Error!usize {
            _ = item_count; // autofix
            var targetbucket: *UntypedBucket = undefined;
            var targetbucketindex: usize = 0;

            for (self.buckets.items, 0..) |*bucket, index| {
                if (bucket.bitmap.mask != 0) {
                    targetbucket = bucket;
                    targetbucketindex = index;
                    break;
                }
            } else {
                targetbucketindex = self.buckets.items.len;
                targetbucket = @ptrCast(try self.do_addOneBucket(self, allocator_));
            }

            return settings.bucket_size * targetbucketindex + targetbucket.bitmap.toggleFirstSet().?;
        }

        pub fn item(self: @This(), comptime Components: []const type, index: usize) !Item(Components) {
            const bucket_index = index / settings.bucket_size;
            const index_in_bucket = index % settings.bucket_size;
            const slices = self.buckets.items[bucket_index].slice(Components);
            var ptrs: Item(Components) = undefined;

            inline for (slices, &ptrs) |sl, *ptr| {
                ptr.* = &sl[index_in_bucket];
            }

            return ptrs;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.do_deinit(self, allocator);
        }
    };
}

test "Db Buckets" {
    const C1 = struct { i32 };
    const C2 = struct { i32 };
    const C3 = struct { i32 };
    // std.debug.print("\n", .{});

    const DbBucketType = DbBucket(&.{ C1, C2, C3 }, .{});

    var bucket = try DbBucketType.init(std.testing.allocator, &.{ C1, C2, C3 });
    defer bucket.deinit(std.testing.allocator);

    for (0..32) |_| {
        // std.debug.print("Allocating item  {} at offset {!}\n", .{ i, bucket.allocateItem(std.testing.allocator) });
    }

    // std.debug.print("Allocating item  {} at offset {!}\n", .{ 32, bucket.allocateItem(std.testing.allocator) });

    var slice_it = try bucket.sliceIterator(&.{C1});
    while (slice_it.next()) |_| {
        // std.debug.print("Slice {any}\n", .{slice});
    }

    // std.debug.print("dbbucket {any}\n", .{bucket});

    // std.debug.print("dbbucket.bucket {any}\n", .{@as(*Bucket(&.{ C1, C2, C3 }, .{}), @ptrCast(@alignCast(&bucket.buckets)))});
}
