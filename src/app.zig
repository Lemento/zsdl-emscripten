// Here why define some defaults for all the apps
// Specifically libraries that need different headers if compiling to native vs web
const builtin = @import("builtin");


pub const PLATFORM = if(builtin.os.tag == .emscripten or builtin.os.tag == .wasi) .WEB else .NATIVE;

pub const sdl = @cImport
({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// const gl = @import("main").gl;
pub const gl = @cImport
({
    if(PLATFORM==.NATIVE)
        @cInclude("glad/glad.h")
    else
    {
        @cInclude("GLES3/gl3.h");
        // @cInclude("EGL/egl.h");
        // @cInclude("EGL/eglext.h");
    }
});
pub const em= struct{
    pub const c= @cImport(if(PLATFORM==.WEB){ @cInclude("emscripten.h"); });

    pub const set_main_loop= c.emscripten_set_main_loop;
    pub const cancel_main_loop= c.emscripten_cancel_main_loop;
};
