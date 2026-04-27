const std = @import("std");

pub const version = "0.0.0-dev";
pub const ast = @import("ast.zig");
pub const diag = @import("diag.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const fmt = @import("fmt.zig");
pub const hir = @import("hir.zig");
pub const flow_ir = @import("flow_ir.zig");
pub const host_schema = @import("host_schema.zig");
pub const io_backend = @import("io_backend.zig");
pub const source_shape = @import("source_shape.zig");
pub const physical_ir = @import("physical_ir.zig");
pub const physical_runtime = @import("physical_runtime.zig");
pub const codegen_zig = @import("codegen_zig.zig");
pub const physical = @import("physical.zig");
pub const headless = @import("headless.zig");
pub const boon_runtime_host = @import("boon_runtime_host.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add" {
    try std.testing.expectEqual(@as(i32, 4), add(2, 2));
}
