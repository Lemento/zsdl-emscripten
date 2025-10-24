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
    
    {
        core_mod.addSystemIncludePath(b.dependency("sdl",.{}).path("include"));
    
        const nk_dep= b.dependency("Nuklear",.{});
        core_mod.addIncludePath(nk_dep.path(""));

        core_mod.addIncludePath(b.path("src/nuklear"));

        core_mod.addCSourceFile(.{.file=b.path("src/nuklear/nuklear_demo.c"), .flags=&.{ "-std=c99", "-Wall", "-Wno-format", "-fno-sanitize=undefined", }});
    }
    core_mod.addIncludePath(b.path("examples"));
    core_mod.addCSourceFile(.{ .file=b.path("examples/stb_image.c"), .flags=&.{ "-std=c89", "-Wall", }});

    const this_mod= b.createModule(.{
        .target=opt.target,
        .optimize=opt.optimize,
        .root_source_file = b.path(src_path),
    });

    core_mod.addImport("impl", this_mod);
    this_mod.addImport("core", core_mod);
    
    return core_mod;
}

const core = @import("core");
const PLATFORM = core.PLATFORM;
const sdl = core.sdl;
const gl = core.gl;
const em = core.emscripten;
const GLPool = core.GLPool;
const Mesh= core.Mesh;
const stb= core.stb_image;

var gpa: core.Allocator= .init;

pub const App= struct{
    window: core.SetupResult= undefined,

    shader_program: core.GLShader = undefined,
    textured: Mesh.Object = undefined,
    texID: gl.GLuint= undefined,
    glPool: GLPool= .empty,

    pub const setup= appSetup;
    pub const init= appInit;
    pub const quit= appQuit;
    pub const event= appEvent;
    pub const iterate= appIterate;
};

const WINDOW_WIDTH:  i32= 600;
const WINDOW_HEIGHT: i32= 600;

const appSetup= core.SetupOptions
{
    .title="textured",
    .width=@intCast(WINDOW_WIDTH),
    .height=@intCast(WINDOW_HEIGHT),
    .bgColor= .{0.0,0.0,0.0},
};

pub fn appInit(app: *App, system: core.SetupResult) anyerror!void
{
    app.window= system;
    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("texture.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("texture.fs"), };

    app.shader_program = try app.glPool.genShader(&vertex_shader_source, &fragment_shader_source);

    // set diffuse sampler early
    app.shader_program.use();
    gl.glUniform1i(app.shader_program.getUniformLocation("diffuse"), 0);

    const vTextured= [_]f32
    {
      0.5,  0.5, 0.0, 1.0, 1.0,  // top right
      0.5, -0.5, 0.0, 1.0, 0.0,  // bottom right
     -0.5, -0.5, 0.0, 0.0, 0.0,  // bottom left
     -0.5,  0.5, 0.0, 0.0, 1.0,  // top left 
    };
    const eTextured= [_]u32
    { 0, 1, 3, 1, 2, 3, };
    const mTextured= Mesh.create(.Textured, &vTextured, &eTextured);
    app.textured= try Mesh.createObject(mTextured, &app.glPool);
    
    // set current working directory
    if (PLATFORM==.WEB) {
        const dir = try std.fs.cwd().openDir("/wasm_data", .{});
        if (@import("builtin").os.tag == .emscripten) {
            try dir.setAsCwd();
        } else if (@import("builtin").os.tag == .wasi) {
            @panic("setting the default current working directory in wasi requires overriding defaultWasiCwd()");
        }
    } else {
        const dir = try std.fs.cwd().openDir("assets", .{});
        try dir.setAsCwd();
    }

    app.texID= try core.loadImage(&app.glPool, "container.jpg");

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

pub fn appEvent(_: *App, evt: sdl.SDL_Event) core.EventFlag
{
    switch(evt.type)
    {
        sdl.SDL_EVENT_QUIT=> return .stop,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(evt.key.key == sdl.SDLK_ESCAPE)
            { return .stop; }
        },
        else=>{},
    }

    return .pass;
}

pub fn appIterate(app: *App) anyerror!bool
{
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    app.shader_program.use();
    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, app.texID);
    app.textured.draw();

    return true;
}
