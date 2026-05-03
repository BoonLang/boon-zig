pub const Example = struct {
    name: []const u8,
    root_path: []const u8,
    entry_file: []const u8,
};

pub const examples = [_]Example{
    .{
        .name = "pong",
        .root_path = "examples/local/pong",
        .entry_file = "pong.bn",
    },
};
