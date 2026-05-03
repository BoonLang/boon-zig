const std = @import("std");

pub const Vertex2D = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32,
};

pub const Batcher = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayListUnmanaged(Vertex2D) = .empty,
    indices: std.ArrayListUnmanaged(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) Batcher {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Batcher) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    pub fn clearRetainingCapacity(self: *Batcher) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    pub fn addVertex(self: *Batcher, vertex: Vertex2D) !u32 {
        const index: u32 = @intCast(self.vertices.items.len);
        try self.vertices.append(self.allocator, vertex);
        return index;
    }

    pub fn addIndex(self: *Batcher, index: u32) !void {
        try self.indices.append(self.allocator, index);
    }
};
