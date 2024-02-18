//! String manipulation tools.
const std = @import("std");

const PrevChar = enum {
    underscore,
    uppercase,
    lowercase,
    other,
};

/// Returns a snake case conversion of the provided pascal case string. Caller owns the allocated string.
pub fn allocSnakeCaseFromPascalCase(str: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // At least as many characyer as in the pascal case string
    try result.ensureTotalCapacity(str.len);

    var prev_char: ?PrevChar = null;

    for (str) |c| {
        switch (c) {
            'A'...'Z' => {
                if (prev_char) |pc| {
                    if (pc == .lowercase or pc == .uppercase) {
                        try result.append('_');
                    }
                }
                prev_char = .uppercase;
                try result.append(std.ascii.toLower(c));
            },
            'a'...'z' => {
                prev_char = .lowercase;
                try result.append(std.ascii.toLower(c));
            },
            else => {
                prev_char = .other;
                try result.append(c);
            },
        }
    }

    return result.toOwnedSlice();
}

/// Returns a pascal case conversion of the provided snake case string. Caller owns the allocated string.
pub fn allocPascalCaseFromSnakeCase(str: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // At least as many characyer as in the pascal case string
    try result.ensureTotalCapacity(str.len);

    var nextisuppercase = true;
    for (str) |c| {
        switch (c) {
            '_' => nextisuppercase = true,
            'A'...'Z', 'a'...'z' => {
                if (nextisuppercase) {
                    try result.append(std.ascii.toUpper(c));
                } else {
                    try result.append(std.ascii.toLower(c));
                }
                nextisuppercase = false;
            },
            else => {
                nextisuppercase = true;
                try result.append(c);
            },
        }
    }

    return result.toOwnedSlice();
}

test "getSnakeCaseFromPascalCase" {
    const tests = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "PascalCaseString", .expected = "pascal_case_string" },
        .{ .input = "camelCaseString", .expected = "camel_case_string" },
        .{ .input = "::AClass::WithinANamespace", .expected = "::a_class::within_a_namespace" },
    };

    for (tests) |t| {
        const snake_case_str = try allocSnakeCaseFromPascalCase(t.input, std.testing.allocator);
        defer std.testing.allocator.free(snake_case_str);
        try std.testing.expectEqualSlices(u8, t.expected, snake_case_str);
    }
}

test "getPascalCaseFromSnakeCase" {
    const tests = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "snake_case_string", .expected = "SnakeCaseString" },
        .{ .input = "SNAKE_CASE_STRING", .expected = "SnakeCaseString" },
        .{ .input = "snake_case::string", .expected = "SnakeCase::String" },
        .{ .input = "::snake_case::string::", .expected = "::SnakeCase::String::" },
    };

    for (tests) |t| {
        const pascal_case_str = try allocPascalCaseFromSnakeCase(t.input, std.testing.allocator);
        defer std.testing.allocator.free(pascal_case_str);
        try std.testing.expectEqualSlices(u8, t.expected, pascal_case_str);
    }
}
