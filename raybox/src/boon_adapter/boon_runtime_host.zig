const std = @import("std");
const boon = @import("boon");

pub const bridge = boon.boon_runtime_host;

pub const MemoryPersistStore = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) MemoryPersistStore {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryPersistStore) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn store(self: *MemoryPersistStore) bridge.PersistStore {
        return .{
            .ptr = self,
            .read = read,
            .write = write,
            .deletePrefix = deletePrefix,
        };
    }

    fn read(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8 {
        const self: *MemoryPersistStore = @ptrCast(@alignCast(ptr));
        const value = self.entries.get(key) orelse return null;
        return try allocator.dupe(u8, value);
    }

    fn write(ptr: *anyopaque, key: []const u8, value: []const u8) anyerror!void {
        const self: *MemoryPersistStore = @ptrCast(@alignCast(ptr));
        if (self.entries.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
        try self.entries.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }

    fn deletePrefix(ptr: *anyopaque, prefix: []const u8) anyerror!void {
        const self: *MemoryPersistStore = @ptrCast(@alignCast(ptr));
        var doomed = std.ArrayListUnmanaged([]const u8).empty;
        defer doomed.deinit(self.allocator);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
                try doomed.append(self.allocator, entry.key_ptr.*);
            }
        }
        for (doomed.items) |key| {
            if (self.entries.fetchRemove(key)) |old| {
                self.allocator.free(old.key);
                self.allocator.free(old.value);
            }
        }
    }
};

pub const MemoryRouteStore = struct {
    route: []const u8 = "/",

    pub fn store(self: *MemoryRouteStore) bridge.RouteStore {
        return .{
            .ptr = self,
            .current = current,
            .goTo = goTo,
        };
    }

    fn current(ptr: *anyopaque) []const u8 {
        const self: *MemoryRouteStore = @ptrCast(@alignCast(ptr));
        return self.route;
    }

    fn goTo(ptr: *anyopaque, route: []const u8) anyerror!void {
        const self: *MemoryRouteStore = @ptrCast(@alignCast(ptr));
        self.route = route;
    }
};
