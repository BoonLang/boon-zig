const std = @import("std");

pub const SourcePayload = enum {
    pulse,
    bool,
    text_change,
    key_event,
    unknown,

    pub fn label(self: SourcePayload) []const u8 {
        return switch (self) {
            .pulse => "Pulse",
            .bool => "Bool",
            .text_change => "TextChange",
            .key_event => "KeyEvent",
            .unknown => "Unknown",
        };
    }
};

pub fn inferSourcePayload(path: []const u8) SourcePayload {
    if (std.mem.endsWith(u8, path, ".hovered")) return .bool;
    if (std.mem.endsWith(u8, path, ".focused")) return .bool;
    if (std.mem.endsWith(u8, path, ".event.change")) return .text_change;
    if (std.mem.endsWith(u8, path, ".event.key_down")) return .key_event;
    if (std.mem.indexOf(u8, path, ".event.") != null) return .pulse;
    return .pulse;
}
