const std = @import("std");

pub const ParseError = error{
    MissingSvgTag,
    MissingAttribute,
    InvalidNumber,
    InvalidColor,
    UnsupportedTag,
    UnsupportedAttribute,
    UnsupportedPathToken,
    OutOfMemory,
};

pub const Color = union(enum) {
    none,
    current_color,
    hex: u32,
};

pub const ViewBox = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const Circle = struct {
    cx: f32,
    cy: f32,
    r: f32,
    fill: Color,
    stroke: Color,
    stroke_width: f32,
};

pub const PathCommandKind = enum { M, L, l, H, V, h, v, C, Z };

pub const PathCommand = struct {
    kind: PathCommandKind,
    values: []const f32,
};

pub const Path = struct {
    fill: Color,
    commands: []const PathCommand,
};

pub const Shape = union(enum) {
    circle: Circle,
    path: Path,
};

pub const Svg = struct {
    width: f32,
    height: f32,
    view_box: ViewBox,
    shapes: []const Shape,

    pub fn deinit(self: *Svg, allocator: std.mem.Allocator) void {
        for (self.shapes) |shape| {
            switch (shape) {
                .path => |path| {
                    for (path.commands) |command| allocator.free(command.values);
                    allocator.free(path.commands);
                },
                .circle => {},
            }
        }
        allocator.free(self.shapes);
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!Svg {
    const svg_tag = findTag(source, "svg") orelse return error.MissingSvgTag;
    const width = try parseFloatAttr(source, svg_tag, "width");
    const height = try parseFloatAttr(source, svg_tag, "height");
    const view_box_text = try attrValue(source, svg_tag, "viewBox");
    const view_box = try parseViewBox(view_box_text);

    var shapes = std.ArrayList(Shape).empty;
    errdefer {
        for (shapes.items) |*shape| switch (shape.*) {
            .path => |path| {
                for (path.commands) |command| allocator.free(command.values);
                allocator.free(path.commands);
            },
            .circle => {},
        };
        shapes.deinit(allocator);
    }

    var cursor: usize = 0;
    while (nextTag(source, &cursor)) |tag| {
        const name = tagName(source, tag);
        if (std.mem.eql(u8, name, "svg")) continue;
        if (std.mem.eql(u8, name, "circle")) {
            try shapes.append(allocator, .{ .circle = try parseCircle(source, tag) });
        } else if (std.mem.eql(u8, name, "path")) {
            try shapes.append(allocator, .{ .path = try parsePath(allocator, source, tag) });
        } else {
            return error.UnsupportedTag;
        }
    }

    return .{
        .width = width,
        .height = height,
        .view_box = view_box,
        .shapes = try shapes.toOwnedSlice(allocator),
    };
}

fn parseCircle(source: []const u8, tag: Tag) ParseError!Circle {
    return .{
        .cx = try parseFloatAttr(source, tag, "cx"),
        .cy = try parseFloatAttr(source, tag, "cy"),
        .r = try parseFloatAttr(source, tag, "r"),
        .fill = try parseColorAttr(source, tag, "fill", .none),
        .stroke = try parseColorAttr(source, tag, "stroke", .none),
        .stroke_width = try parseOptionalFloatAttr(source, tag, "stroke-width", 0),
    };
}

fn parsePath(allocator: std.mem.Allocator, source: []const u8, tag: Tag) ParseError!Path {
    const fill = try parseColorAttr(source, tag, "fill", .none);
    const data = try attrValue(source, tag, "d");
    return .{
        .fill = fill,
        .commands = try parsePathData(allocator, data),
    };
}

fn parsePathData(allocator: std.mem.Allocator, data: []const u8) ParseError![]const PathCommand {
    var commands = std.ArrayList(PathCommand).empty;
    errdefer {
        for (commands.items) |command| allocator.free(command.values);
        commands.deinit(allocator);
    }

    var cursor: usize = 0;
    var current: ?u8 = null;
    while (true) {
        skipPathSeparators(data, &cursor);
        if (cursor >= data.len) break;
        const byte = data[cursor];
        if (std.ascii.isAlphabetic(byte)) {
            current = byte;
            cursor += 1;
        } else if (current == null) {
            return error.UnsupportedPathToken;
        }
        const command = current.?;
        switch (command) {
            'M', 'L', 'l' => {
                var first = true;
                while (try readNumberPair(allocator, data, &cursor)) |values| {
                    try commands.append(allocator, .{ .kind = if (first) pathKind(command) else pathKind(if (command == 'M') 'L' else command), .values = values });
                    first = false;
                    skipPathSeparators(data, &cursor);
                    if (cursor >= data.len or std.ascii.isAlphabetic(data[cursor])) break;
                }
                if (first) return error.UnsupportedPathToken;
            },
            'H', 'V', 'h', 'v' => {
                var read_any = false;
                while (try readSingleNumber(allocator, data, &cursor)) |values| {
                    read_any = true;
                    try commands.append(allocator, .{ .kind = pathKind(command), .values = values });
                    skipPathSeparators(data, &cursor);
                    if (cursor >= data.len or std.ascii.isAlphabetic(data[cursor])) break;
                }
                if (!read_any) return error.UnsupportedPathToken;
            },
            'C' => {
                var read_any = false;
                while (try readNumbers(allocator, data, &cursor, 6)) |values| {
                    read_any = true;
                    try commands.append(allocator, .{ .kind = .C, .values = values });
                    skipPathSeparators(data, &cursor);
                    if (cursor >= data.len or std.ascii.isAlphabetic(data[cursor])) break;
                }
                if (!read_any) return error.UnsupportedPathToken;
            },
            'Z', 'z' => try commands.append(allocator, .{ .kind = .Z, .values = &.{} }),
            else => return error.UnsupportedPathToken,
        }
        if (command == 'Z' or command == 'z') current = null;
    }
    return try commands.toOwnedSlice(allocator);
}

fn readNumberPair(allocator: std.mem.Allocator, data: []const u8, cursor: *usize) ParseError!?[]const f32 {
    return try readNumbers(allocator, data, cursor, 2);
}

fn readSingleNumber(allocator: std.mem.Allocator, data: []const u8, cursor: *usize) ParseError!?[]const f32 {
    return try readNumbers(allocator, data, cursor, 1);
}

fn readNumbers(allocator: std.mem.Allocator, data: []const u8, cursor: *usize, count: usize) ParseError!?[]const f32 {
    skipPathSeparators(data, cursor);
    if (cursor.* >= data.len or std.ascii.isAlphabetic(data[cursor.*])) return null;
    const values = try allocator.alloc(f32, count);
    errdefer allocator.free(values);
    for (values) |*value| {
        skipPathSeparators(data, cursor);
        value.* = try parsePathNumber(data, cursor);
    }
    return values;
}

fn parsePathNumber(data: []const u8, cursor: *usize) ParseError!f32 {
    const start = cursor.*;
    if (cursor.* < data.len and (data[cursor.*] == '-' or data[cursor.*] == '+')) cursor.* += 1;
    var saw_digit = false;
    while (cursor.* < data.len and std.ascii.isDigit(data[cursor.*])) : (cursor.* += 1) saw_digit = true;
    if (cursor.* < data.len and data[cursor.*] == '.') {
        cursor.* += 1;
        while (cursor.* < data.len and std.ascii.isDigit(data[cursor.*])) : (cursor.* += 1) saw_digit = true;
    }
    if (!saw_digit) return error.InvalidNumber;
    return std.fmt.parseFloat(f32, data[start..cursor.*]) catch error.InvalidNumber;
}

fn pathKind(byte: u8) PathCommandKind {
    return switch (byte) {
        'M' => .M,
        'L' => .L,
        'l' => .l,
        'H' => .H,
        'V' => .V,
        'h' => .h,
        'v' => .v,
        else => .Z,
    };
}

fn skipPathSeparators(data: []const u8, cursor: *usize) void {
    while (cursor.* < data.len and (std.ascii.isWhitespace(data[cursor.*]) or data[cursor.*] == ',')) cursor.* += 1;
}

fn parseViewBox(text: []const u8) ParseError!ViewBox {
    var cursor: usize = 0;
    skipPathSeparators(text, &cursor);
    const x = try parsePathNumber(text, &cursor);
    skipPathSeparators(text, &cursor);
    const y = try parsePathNumber(text, &cursor);
    skipPathSeparators(text, &cursor);
    const w = try parsePathNumber(text, &cursor);
    skipPathSeparators(text, &cursor);
    const h = try parsePathNumber(text, &cursor);
    return .{ .x = x, .y = y, .w = w, .h = h };
}

const Tag = struct {
    start: usize,
    end: usize,
};

fn findTag(source: []const u8, comptime name: []const u8) ?Tag {
    var cursor: usize = 0;
    while (nextTag(source, &cursor)) |tag| {
        if (std.mem.eql(u8, tagName(source, tag), name)) return tag;
    }
    return null;
}

fn nextTag(source: []const u8, cursor: *usize) ?Tag {
    const open_rel = std.mem.indexOfScalarPos(u8, source, cursor.*, '<') orelse return null;
    const open = open_rel;
    if (open + 1 < source.len and source[open + 1] == '!') {
        cursor.* = open + 1;
        return nextTag(source, cursor);
    }
    const close = std.mem.indexOfScalarPos(u8, source, open, '>') orelse return null;
    cursor.* = close + 1;
    return .{ .start = open, .end = close + 1 };
}

fn tagName(source: []const u8, tag: Tag) []const u8 {
    var start = tag.start + 1;
    while (start < tag.end and std.ascii.isWhitespace(source[start])) start += 1;
    if (start < tag.end and source[start] == '/') start += 1;
    var end = start;
    while (end < tag.end and !std.ascii.isWhitespace(source[end]) and source[end] != '>' and source[end] != '/') end += 1;
    return source[start..end];
}

fn attrValue(source: []const u8, tag: Tag, name: []const u8) ParseError![]const u8 {
    const body = source[tag.start..tag.end];
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, body, cursor, name)) |found| {
        const after_name = found + name.len;
        if (found != 0 and isAttrNameByte(body[found - 1])) {
            cursor = after_name;
            continue;
        }
        var index = after_name;
        while (index < body.len and std.ascii.isWhitespace(body[index])) index += 1;
        if (index >= body.len or body[index] != '=') {
            cursor = after_name;
            continue;
        }
        index += 1;
        while (index < body.len and std.ascii.isWhitespace(body[index])) index += 1;
        if (index >= body.len or body[index] != '"') return error.UnsupportedAttribute;
        index += 1;
        const value_start = index;
        while (index < body.len and body[index] != '"') index += 1;
        if (index >= body.len) return error.UnsupportedAttribute;
        return body[value_start..index];
    }
    return error.MissingAttribute;
}

fn isAttrNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == ':';
}

fn parseFloatAttr(source: []const u8, tag: Tag, name: []const u8) ParseError!f32 {
    return std.fmt.parseFloat(f32, try attrValue(source, tag, name)) catch error.InvalidNumber;
}

fn parseOptionalFloatAttr(source: []const u8, tag: Tag, name: []const u8, default: f32) ParseError!f32 {
    const value = attrValue(source, tag, name) catch |err| switch (err) {
        error.MissingAttribute => return default,
        else => return err,
    };
    return std.fmt.parseFloat(f32, value) catch error.InvalidNumber;
}

fn parseColorAttr(source: []const u8, tag: Tag, name: []const u8, default: Color) ParseError!Color {
    const value = attrValue(source, tag, name) catch |err| switch (err) {
        error.MissingAttribute => return default,
        else => return err,
    };
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "currentColor")) return .current_color;
    if (value.len == 7 and value[0] == '#') {
        return .{ .hex = std.fmt.parseInt(u32, value[1..], 16) catch return error.InvalidColor };
    }
    return error.InvalidColor;
}

test "svg_minimal parses pinned checkbox icon subset" {
    const source =
        \\<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="-10 -18 100 135"><circle cx="50" cy="50" r="50" fill="none" stroke="#bddad5" stroke-width="3"/><path fill="#5dc2af" d="M72 25L42 71 27 56l-4 4 20 20 34-52z"/></svg>
    ;
    var svg = try parse(std.testing.allocator, source);
    defer svg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), svg.shapes.len);
}
