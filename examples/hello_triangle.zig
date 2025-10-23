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

    return core_mod;
}

const core = @import("core");
const PLATFORM = core.PLATFORM;
const sdl = core.sdl;
const gl = core.gl;
const em = core.emscripten;
const GLPool = core.GLPool;
const Mesh= core.Mesh;

var gpa: core.Allocator= .init;

pub const App= struct{
    window: core.InitResult= undefined,

    shader_program: core.GLShader = undefined,
    triangle: Mesh.Object = undefined,
    square: Mesh.Object = undefined,
    display_obj: Mesh.Object = undefined,
    glPool: GLPool= .empty,

    pub const setup= setupOptions;
    pub const init= appInit;
    pub const quit= appQuit;
    pub const event= appEvent;
    pub const iterate= appIterate;
};

const WINDOW_WIDTH:  i32= 600;
const WINDOW_HEIGHT: i32= 600;

const setupOptions= core.InitOptions
{
  .title="hello_triangle",
  .width=@intCast(WINDOW_WIDTH),
  .height=@intCast(WINDOW_HEIGHT),
  .bgColor=.{0.0,0.0,0.0},
};
pub fn appInit(app: *App, system: core.InitResult) anyerror!void
{
    app.window= system;

    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("color.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("color.fs"), };

    app.shader_program = try app.glPool.genShader(&vertex_shader_source, &fragment_shader_source);

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
    app.display_obj= app.triangle;

    const vSquare= [_]f32
    {
      // first triangle
      0.5,  0.5, 0.0,  // top right
      0.5, -0.5, 0.0,  // bottom right
     -0.5, -0.5, 0.0,  // bottom left
     -0.5,  0.5, 0.0,  // top left 
    };
    const eSquare= [_]u32
    { 0, 1, 3, 1, 2, 3, };
    const mSquare= Mesh.create(.OnlyPosition, &vSquare, &eSquare);
    app.square= try Mesh.createObject(mSquare, &app.glPool);
    
    try app.window.show();
}

pub fn appQuit(app: *App) void
{
    std.log.debug("Cleaning Up!", .{});
    
    defer if(PLATFORM==.NATIVE) {
        if(gpa.deinit() == .leak)
        { std.testing.expect(false) catch @panic("MEMORY LEAK!"); }
    };

    app.glPool.deinit();
}

pub fn appEvent(app: *App, evt: sdl.SDL_Event) core.EventFlag
{
    switch(evt.type)
    {
        sdl.SDL_EVENT_QUIT=> return .stop,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(evt.key.key == sdl.SDLK_ESCAPE)
            { return .stop; }

            if(evt.key.key == sdl.SDLK_1)
            { app.display_obj= app.triangle; }
            if(evt.key.key == sdl.SDLK_2)
            { app.display_obj= app.square; }
        },
        else=>{},
    }

    return .pass;
}

pub fn appIterate(app: *App) anyerror!bool
{
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glUseProgram(app.shader_program.id);
    app.display_obj.draw();

    return true;
}
