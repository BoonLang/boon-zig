# Text Vendoring

The v0 text stack is FontStash plus stb_truetype with a dynamic bitmap glyph atlas.

Vendored files:

- `fontstash.h`: FontStash from `memononen/fontstash` commit `b5ddc9741061343740d85d636d782ed3e07cf7be`
- `stb_truetype.h`: stb from `nothings/stb` commit `31c1ad37456438565541f4919958214b6e762fb4`

Local patches:

- None. `fontstash_impl.c` is only the translation unit that defines `FONTSTASH_IMPLEMENTATION` and includes the vendored header.

Core fonts are embedded with `@embedFile` from `assets/fonts/` so native and web builds can measure first-frame text without an asynchronous asset race.
