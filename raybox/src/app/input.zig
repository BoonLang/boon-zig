const sdl = @import("sdl");

const c = sdl.c;

pub const InputState = struct {
    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    pointer_down: bool = false,
    events_this_frame: u32 = 0,

    pub fn record(self: *InputState, ev: *const c.SDL_Event) void {
        self.events_this_frame +|= 1;
        switch (ev.type) {
            c.SDL_EVENT_MOUSE_MOTION => {
                self.pointer_x = ev.motion.x;
                self.pointer_y = ev.motion.y;
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => self.pointer_down = true,
            c.SDL_EVENT_MOUSE_BUTTON_UP => self.pointer_down = false,
            else => {},
        }
    }

    pub fn endFrame(self: *InputState) void {
        self.events_this_frame = 0;
    }
};
