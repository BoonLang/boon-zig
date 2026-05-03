const sdl = @import("sdl");

const c = sdl.c;

pub const AppClock = struct {
    last_time: u64 = 0,
    delta_seconds: f64 = 0,

    pub fn reset(self: *AppClock) void {
        self.last_time = c.SDL_GetTicksNS();
        self.delta_seconds = 0;
    }

    pub fn tick(self: *AppClock) void {
        const now: u64 = c.SDL_GetTicksNS();
        self.delta_seconds = @as(f64, @floatFromInt(now - self.last_time)) / 1_000_000_000.0;
        self.last_time = now;
    }
};
