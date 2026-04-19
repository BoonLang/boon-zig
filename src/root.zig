const std = @import("std");

pub const version = "0.0.0-dev";
pub const ast = @import("ast.zig");
pub const diag = @import("diag.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const fmt = @import("fmt.zig");
pub const hir = @import("hir.zig");
pub const flow_ir = @import("flow_ir.zig");
pub const io_backend = @import("io_backend.zig");
pub const physical = @import("physical.zig");
pub const headless = @import("headless.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add" {
    try std.testing.expectEqual(@as(i32, 4), add(2, 2));
}
