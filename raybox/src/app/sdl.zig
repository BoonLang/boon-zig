pub const c = @cImport({
    @cDefine("SDL_STATIC_LIB", "1");
    @cInclude("SDL3/SDL.h");
});
