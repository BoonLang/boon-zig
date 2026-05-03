pub const FrameStats = struct {
    frame_index: u64 = 0,
    delta_seconds: f64 = 0,
    draw_batches: u32 = 0,
    vertices: u32 = 0,
    indices: u32 = 0,
    glyph_uploads: u32 = 0,
    shadow_cache_hits: u32 = 0,
    shadow_cache_misses: u32 = 0,
    frame_arena_high_water: usize = 0,

    pub fn beginFrame(self: *FrameStats, delta_seconds: f64) void {
        self.delta_seconds = delta_seconds;
        self.draw_batches = 0;
        self.vertices = 0;
        self.indices = 0;
        self.glyph_uploads = 0;
        self.shadow_cache_hits = 0;
        self.shadow_cache_misses = 0;
        self.frame_arena_high_water = 0;
    }

    pub fn endFrame(self: *FrameStats) void {
        self.frame_index +|= 1;
    }
};
