const std = @import("std");

/// Make an example demo that opens a window with a triangle built from vertices loaded to the gpu
/// Uses SDL3 and OpenGL
/// Create wrapper functions for sdl and opengl

pub fn build(b: *std.Build, src_path: []const u8, opt:anytype) *std.Build.Module
{
    // build core.zig as the module that has 'main' in it and return it
    const core_mod = b.createModule(.{
        .target = opt.target,
        .optimize = opt.optimize,
        .root_source_file = b.path("examples/core.zig"),
        .link_libc = true,
    });

    const impl_mod= b.createModule(.{
        .target=opt.target,
        .optimize=opt.optimize,
        .root_source_file = b.path(src_path),
    });

    core_mod.addImport("impl", impl_mod);
    impl_mod.addImport("core", core_mod);

    const zmath= b.dependency("zmath", .{});
    impl_mod.addImport("zmath", zmath.module("root"));

    return core_mod;
}

const core = @import("core");
const PLATFORM = core.PLATFORM;
const sdl = core.sdl;
const gl = core.gl;
const em = core.emscripten;
const GLPool = core.GLPool;
const Mesh = core.Mesh;
const Object= Mesh.Object;

const zm = @import("zmath");

var gpa: core.Allocator= .init;

pub const App= struct{
    window: core.InitResult= undefined,

    press_up: bool= false,
    press_down: bool= false,
    press_left: bool= false,
    press_right: bool= false,

    shader_program: core.GLShader = undefined,
    triangle: Object = undefined,
    glPool: GLPool= .empty,

    pub const init= appInit;
    pub const quit= appQuit;
    pub const event= appEvent;
    pub const iterate= appIterate;
};

const WINDOW_WIDTH:  i32= 600;
const WINDOW_HEIGHT: i32= 600;

pub fn appInit(app: *App) !void
{
    app.window= try core.initSDLandOpenGL("hello_triangle", WINDOW_WIDTH, WINDOW_HEIGHT, .{});

    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("transforms.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("basic.fs"), };

    app.shader_program = try app.glPool.genShader(&vertex_shader_source, &fragment_shader_source);

    const transform= zm.identity();
    gl.glUseProgram(app.shader_program.id);
    // Reminder that opengl uses column-major matrices while
    // zmath matrices are row-major, so in order for the math to stay 
    // consistent you either tell opengl to transpose it by sending
    // GL_TRUE, calculate the transposition earlier with zm.transpose, or
    // move around the order of operations in the shader.
    gl.glUniformMatrix4fv(gl.glGetUniformLocation(app.shader_program.id, "transform"), 1, gl.GL_FALSE, &transform[0][0]);
    std.log.debug("Press Arrow keys for transform",.{});

    // triangle vertices
    const vTriangle= [_]f32
    {
    // positions       colors
      0.5, -0.5, 0.0, 1.0, 0.0, 0.0,
     -0.5, -0.5, 0.0, 0.0, 1.0, 0.0,
      0.0,  0.5, 0.0, 0.0, 0.0, 1.0,
    };
    const mTriangle= Mesh.create(.PosAndColor, &vTriangle, &.{});

    app.triangle= try Mesh.createObject(mTriangle, &app.glPool);
    
    _=sdl.SDL_ShowWindow(app.window.screen);
}

pub fn appQuit(app: *App) void
{
    std.log.debug("Cleaning Up!", .{});
    
    defer if(PLATFORM==.NATIVE) {
        if(gpa.deinit() == .leak)
        { std.testing.expect(false) catch @panic("MEMORY LEAK!"); }
    };

    // Deallocate all memory here please
    app.glPool.deinit();

    _=sdl.SDL_GL_DestroyContext(app.window.glContext);
    sdl.SDL_DestroyWindow(app.window.screen);
    sdl.SDL_Quit();
}

pub fn appEvent(app: *App, evt: sdl.SDL_Event) !void
{
    switch(evt.type)
    {
        sdl.SDL_EVENT_QUIT=> return error.RuntimeRequestQuit,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(evt.key.key == sdl.SDLK_ESCAPE)
            { return error.RuntimeRequestQuit; }
        
            switch(evt.key.key)
            {
                sdl.SDLK_UP=> app.press_up= true,
                sdl.SDLK_DOWN=> app.press_down= true,
                sdl.SDLK_LEFT=> app.press_left= true,
                sdl.SDLK_RIGHT=> app.press_right= true,
                else=>{},
            }
        },
        sdl.SDL_EVENT_KEY_UP=>
        {
            switch(evt.key.key)
            {
                sdl.SDLK_UP=>    app.press_up= false,
                sdl.SDLK_DOWN=>  app.press_down= false,
                sdl.SDLK_LEFT=>  app.press_left= false,
                sdl.SDLK_RIGHT=> app.press_right= false,
                else=>{},
            }
        },
        else=>{},
    }
}

pub fn appIterate(app: *App) !void
{
    var transform= zm.identity();
    if(app.press_up)
    { transform= zm.mul(transform, zm.translation(0, 1,0)); }
    else if(app.press_down)
    { transform= zm.mul(transform, zm.translation(0,-1,0)); }

    if(app.press_left)
    { transform= zm.mul(transform, zm.translation(-1,0,0)); }
    else if(app.press_right)
    { transform= zm.mul(transform, zm.translation( 1,0,0)); }

    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glUseProgram(app.shader_program.id);

    gl.glUniformMatrix4fv(gl.glGetUniformLocation(app.shader_program.id, "transform"), 1, gl.GL_FALSE, &transform[0][0]);
    app.triangle.draw();
    
    _=sdl.SDL_GL_SwapWindow(app.window.screen);
}
