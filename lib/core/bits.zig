//! Bit manipulation utilities.
const builtin = @import("builtin");
const std = @import("std");

/// Deposit contiguous low bits from unsigned 64-bit integer a to dst at the corresponding bit locations specified by mask
/// All other bits in dst are set to zero.
/// Mimics the x64_64 bmi2 intrinsic.
fn pdepU64(x: u64, mask: u64) u64 {
    if (comptime std.Target.Cpu.Arch.isX86(builtin.cpu.arch)) {
        if (comptime std.Target.Cpu.Feature.Set.isEnabled(builtin.cpu.features, @intFromEnum(std.Target.x86.Feature.bmi2))) {
            return asm (
                \\ pdepq %[mask], %[x], %[out]
                : [out] "=r" (-> u64),
                : [mask] "r" (mask),
                  [x] "r" (x),
            );
        }
    }

    var result: u64 = 0;
    var mask_mut: u64 = mask;

    // For each 1 bit in the mask, get the matching value in x
    // and copy it in the output location
    for (0..@popCount(mask)) |i| {
        const bitshift: u6 = @intCast(@ctz(mask_mut));
        const bitmask = @shlExact(@as(u64, 1), bitshift);
        const src_bitmask = @as(u64, 1) << @intCast(i);
        const bit = @shlExact(x & src_bitmask, @intCast(bitshift - i));
        result |= bit;
        mask_mut ^= bitmask;
    }
    return result;
}

/// Extract bits from unsigned 64-bit integer a at the corresponding bit locations specified by mask to contiguous low bits in dst;
/// The remaining upper bits in dst are set to zero.
/// Mimics the x86_64 bmi2 intrinsic.
fn pextU64(x: u64, mask: u64) u64 {
    if (comptime std.Target.Cpu.Arch.isX86(builtin.cpu.arch)) {
        if (comptime std.Target.Cpu.Feature.Set.isEnabled(builtin.cpu.features, @intFromEnum(std.Target.x86.Feature.bmi2))) {
            return asm (
                \\ pextq %[mask], %[x],%[out]
                : [out] "=r" (-> u64),
                : [mask] "r" (mask),
                  [x] "r" (x),
            );
        }
    }

    var result: u64 = 0;
    var mask_mut: u64 = mask;

    // For each 1 bit in the mask, get the matching value in x
    // and copy it in the output location
    for (0..@popCount(mask)) |i| {
        const bitshift: u6 = @intCast(@ctz(mask_mut));
        const bitmask = @shlExact(@as(u64, 1), bitshift);
        const bit = @shrExact(x & bitmask, @intCast(bitshift - i));
        result |= bit;
        mask_mut ^= bitmask;
    }
    return result;
}

/// Pack two values interleaving bits.
/// 0baaaa 0bbbbb => 0xbabababa.
pub fn getInterleavedBits(a: u32, b: u32) u64 {
    return pdepU64(a, 0x5555555555555555) | pdepU64(b, 0xaaaaaaaaaaaaaaaa);
}

test "getInterleavedBits" {
    try std.testing.expectEqual(@as(u64, 3), getInterleavedBits(1, 1));
    try std.testing.expectEqual(@as(u64, 0x5555555555555555), getInterleavedBits(0xffffffff, 0));
    try std.testing.expectEqual(@as(u64, 0xaaaaaaaaaaaaaaaa), getInterleavedBits(0, 0xffffffff));
}

const DeinterleavedBits = struct {
    a: u32,
    b: u32,
};

/// Unpack interleaving bits into two separate values.
/// 0xbabababa => 0baaaa 0bbbbb.
pub fn getDeinterleavedBits(a: u64) DeinterleavedBits {
    return .{
        .a = @intCast(pextU64(a, 0x5555555555555555)),
        .b = @intCast(pextU64(a, 0xaaaaaaaaaaaaaaaa)),
    };
}

test "getDeinterleavedBits" {
    try std.testing.expectEqual(DeinterleavedBits{ .a = 1, .b = 1 }, getDeinterleavedBits(3));
    try std.testing.expectEqual(DeinterleavedBits{ .a = 0xffffffff, .b = 0 }, getDeinterleavedBits(0x5555555555555555));
    try std.testing.expectEqual(DeinterleavedBits{ .a = 0, .b = 0xffffffff }, getDeinterleavedBits(0xaaaaaaaaaaaaaaaa));
}

/// Returns true if the provided int starts with len bits on.
pub fn startsWithNthBitsSet(int: anytype, len: usize) bool {
    const IntType = @TypeOf(int);
    const int_type = @typeInfo(IntType);

    comptime std.debug.assert(int_type == .Int);
    std.debug.assert(len <= int_type.Int.bits);

    // Simply build a mask and use it to compare with the provided int.
    const mask = ~(~@as(IntType, 0) << @intCast(len));
    return int & mask == mask;
}

test "startsWithNthBitsSet" {
    const tests = [_]struct { input: struct { u8, usize }, expected: bool }{
        .{ .input = .{ 0b0001_1111, 5 }, .expected = true },
        .{ .input = .{ 0b0001_1111, 6 }, .expected = false },
        .{ .input = .{ 0b0001_1110, 5 }, .expected = false },
    };

    for (tests) |t| {
        try std.testing.expectEqual(startsWithNthBitsSet(t.input[0], t.input[1]), t.expected);
    }
}

/// Returns true if the provided int ends with len bits on.
pub fn endsWithNthBitsSet(int: anytype, len: usize) bool {
    const IntType = @TypeOf(int);
    const int_type = @typeInfo(IntType);

    comptime std.debug.assert(int_type == .Int);
    std.debug.assert(len <= int_type.Int.bits);

    // Simply build a mask and use it to compare with the provided int.
    const mask = ~(~@as(IntType, 0) >> @intCast(len));
    return int & mask == mask;
}

test "endsWithNthBitsSet" {
    const tests = [_]struct { input: struct { u8, usize }, expected: bool }{
        .{ .input = .{ 0b1111_1000, 5 }, .expected = true },
        .{ .input = .{ 0b1111_1000, 6 }, .expected = false },
        .{ .input = .{ 0b0111_1000, 5 }, .expected = false },
    };

    for (tests) |t| {
        try std.testing.expectEqual(endsWithNthBitsSet(t.input[0], t.input[1]), t.expected);
    }
}

const BitRange = struct {
    start: usize,
    len: usize,
};

/// Return the longest 1 bits sequence in the provided int.
pub fn findLongestBitsSetSequence(int: anytype) ?BitRange {
    const IntType = @TypeOf(int);
    const int_type = @typeInfo(IntType);
    comptime std.debug.assert(int_type == .Int);

    // A bit trickier than the algorithms above. Shift and mask the provided int with itself.
    // Two consecutive 1s will stay as one 1. Repeat until int combined it is 0.
    var len: usize = 0;
    var prevtrimmed = int;
    var trimmed = int;

    while (trimmed != 0) {
        len += 1;
        prevtrimmed = trimmed;
        trimmed &= trimmed >> 1;
    }

    if (len == 0)
        return null
    else
        return .{
            .start = @ctz(prevtrimmed),
            .len = len,
        };
}

test "findLongestBitsSetSequence" {
    const tests = [_]struct { input: u8, expected: ?BitRange }{
        .{ .input = 0b1110_1100, .expected = .{ .start = 5, .len = 3 } },
        .{ .input = 0b1100_1110, .expected = .{ .start = 1, .len = 3 } },
        .{ .input = 0b1110_1110, .expected = .{ .start = 1, .len = 3 } },
        .{ .input = 0b1111_1111, .expected = .{ .start = 0, .len = 8 } },

        .{ .input = 0, .expected = null },
    };

    for (tests) |t| {
        try std.testing.expectEqual(t.expected, findLongestBitsSetSequence(t.input));
    }
}

/// Return the first 1 bits sequence in the provided int that is at least min_len bits.
pub fn findFirstBitsSetSequenceAtLeast(int: anytype, min_len: usize) ?BitRange {
    const IntType = @TypeOf(int);
    const int_type = @typeInfo(IntType);
    comptime std.debug.assert(int_type == .Int);

    // Variation on the above. Combine shift for min_len - 1 iteration.
    // The first 1 to be found is a valid candidate.
    var trimmed = int;
    for (1..min_len) |_| {
        trimmed &= trimmed >> 1;
    }

    if (trimmed == 0)
        return null
    else
        return .{
            .start = @ctz(trimmed),
            .len = min_len,
        };

    return null;
}

test "findFirstBitsSetSequenceAtLeast" {
    const tests = [_]struct { input: struct { u8, usize }, expected: ?BitRange }{
        .{ .input = .{ 0b1110_1100, 3 }, .expected = .{ .start = 5, .len = 3 } },
        .{ .input = .{ 0b1110_1110, 3 }, .expected = .{ .start = 1, .len = 3 } },
        .{ .input = .{ 0b0110_1110, 3 }, .expected = .{ .start = 1, .len = 3 } },
        .{ .input = .{ 0b0110_0110, 3 }, .expected = null },
    };

    for (tests) |t| {
        try std.testing.expectEqual(t.expected, findFirstBitsSetSequenceAtLeast(t.input[0], t.input[1]));
    }
}

/// Return the shortest 1 bits sequence in the provided int that is at least min_len bits.
pub fn findShortestBitsSetSequenceAtLeast(int: anytype, min_len: usize) ?BitRange {
    const IntType = @TypeOf(int);
    const int_type = @typeInfo(IntType);
    comptime std.debug.assert(int_type == .Int);

    // Variation on the above. Combine shift for min_len - 1 iteration.
    // Candidates will be all those blocks with at least one 1.
    var trimmed = int;
    for (1..min_len) |_| {
        trimmed &= trimmed >> 1;
    }

    // Kill the singluar 1s. The remaing 1s are then part of larger blocks of 1s.
    const mask = trimmed & (trimmed >> 1);
    // Build another mask to kill those blobs.
    const combinedmask = mask | (mask << 1);

    // And use that remove all but singular 1s in the trimmed int.
    trimmed = trimmed & ~combinedmask;

    // All singular 1s are valid results. Pick the first one.
    if (trimmed == 0)
        return null
    else
        return .{
            .start = @ctz(trimmed),
            .len = min_len,
        };
}

test "findShortestBitsSetSequenceAtLeast" {
    const tests = [_]struct { input: struct { u8, usize }, expected: ?BitRange }{
        .{ .input = .{ 0b1111_0111, 3 }, .expected = .{ .start = 0, .len = 3 } },
        .{ .input = .{ 0b1110_1111, 3 }, .expected = .{ .start = 5, .len = 3 } },
        .{ .input = .{ 0b0110_0110, 4 }, .expected = null },
        .{ .input = .{ 0b1110_1110, 3 }, .expected = .{ .start = 1, .len = 3 } },
        .{ .input = .{ 0b0000_0000, 3 }, .expected = null },
        .{ .input = .{ 0b1111_1111, 8 }, .expected = .{ .start = 0, .len = 8 } },
    };

    for (tests) |t| {
        try std.testing.expectEqual(t.expected, findShortestBitsSetSequenceAtLeast(t.input[0], t.input[1]));
    }
}
