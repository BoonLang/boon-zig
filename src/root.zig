const std = @import("std");

pub const version = "0.0.0-dev";

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add" {
    try std.testing.expectEqual(@as(i32, 4), add(2, 2));
}
