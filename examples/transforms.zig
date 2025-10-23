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

    { // Link Nuklear ui
        core_mod.addSystemIncludePath(b.dependency("sdl",.{}).path("include"));
    
        const nk_dep= b.dependency("Nuklear",.{});
        core_mod.addIncludePath(nk_dep.path(""));

        core_mod.addIncludePath(b.path("src/nuklear"));

        core_mod.addCSourceFile(.{.file=b.path("src/nuklear/nuklear_demo.c"), .flags=&.{ "-std=c99", "-Wall", "-Wno-format", "-fno-sanitize=undefined", }});
    }

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

    moveDirV:f32=0.0,
    moveDirH:f32=0.0,
    press_up: bool= false,
    press_down: bool= false,
    press_left: bool= false,
    press_right: bool= false,

    shader_program: core.GLShader = undefined,
    triangle: Object = undefined,
    glPool: GLPool= .empty,

    pub const setup= appSetup;
    pub const init= appInit;
    pub const quit= appQuit;
    pub const event= appEvent;
    pub const iterate= appIterate;
};

const WINDOW_WIDTH:  i32= 600;
const WINDOW_HEIGHT: i32= 600;

const appSetup= core.InitOptions
{
    .title="transforms",
    .width=@intCast(WINDOW_WIDTH), .height=@intCast(WINDOW_HEIGHT),
    .setVSync= -1,
};

pub fn appInit(app: *App, system: core.InitResult) anyerror!void
{
    app.window= system;
    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("transforms.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("basic.fs"), };

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
    
    std.log.debug("Press Arrow keys for transform",.{});
    try app.window.show();
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
}

pub fn appEvent(app: *App, evt: sdl.SDL_Event) core.EventFlag
{
    switch(evt.type)
    {
        sdl.SDL_EVENT_QUIT=> return .stop,
        sdl.SDL_EVENT_KEY_DOWN,sdl.SDL_EVENT_KEY_UP=>
        {
            if(evt.key.key == sdl.SDLK_ESCAPE)
            { return .stop; }
        
            const pressed= (evt.type==sdl.SDL_EVENT_KEY_DOWN);
            switch(evt.key.key)
            {
                sdl.SDLK_UP=>
                {
                  app.press_up= pressed;
                  if(pressed) app.moveDirV=1.0
                  else if(app.press_down) app.moveDirV=-1.0;
                },
                sdl.SDLK_DOWN=>
                {
                  app.press_down= pressed;
                  if(pressed) app.moveDirV=-1.0
                  else if(app.press_up) app.moveDirV=1.0;
                },
                sdl.SDLK_LEFT=>
                {
                  app.press_left= pressed;
                  if(pressed) app.moveDirH=-1.0
                  else if(app.press_right) app.moveDirH=1.0;
                },
                sdl.SDLK_RIGHT=>
                {
                  app.press_right= pressed;
                  if(pressed) app.moveDirH=1.0
                  else if(app.press_left) app.moveDirH=-1.0;
                },
                else=>{},
            }
        },else=>{},
    }

    return .pass;
}

const nk= core.nuklear;
var transform= zm.identity();
pub fn appIterate(app: *App) anyerror!bool
{
    var move=zm.Vec{0.0,0.0,0.0,1.0};
    const vScale: zm.Vec=.{0.1, 0.1, 0.1, 1.0};

    if(app.press_up or app.press_down)
    { move[1]= app.moveDirV; }

    if(app.press_left or app.press_right)
    { move[0]= app.moveDirH; }

    transform= zm.mul(transform, zm.translationV(zm.normalize4(move)*vScale));
    
    {
        const ui_win= struct
        {
            var open= true;
        };
        const ctx= app.window.nkx;
        //* GUI */
        ui_win.open= (nk.nk_begin(app.window.nkx, "Demo", nk.nk_rect(5, 5, 230, 250),
            nk.NK_WINDOW_BORDER|nk.NK_WINDOW_MOVABLE|nk.NK_WINDOW_SCALABLE |
            nk.NK_WINDOW_MINIMIZABLE|nk.NK_WINDOW_TITLE) == 1);
        if(ui_win.open)
        {
            nk.nk_layout_row_dynamic(ctx, 22.0, 1);
            nk.nk_labelf(ctx, nk.NK_TEXT_LEFT, "triangle[%3.2f, %3.2f, %3.2f]", transform[3][0], transform[3][1], transform[3][2]);
        }
        nk.nk_end(ctx);
    }
    
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glUseProgram(app.shader_program.id);

    // Reminder that opengl uses column-major matrices while
    // zmath matrices are row-major, so in order for the math to stay 
    // consistent you either tell opengl to transpose it by sending
    // GL_TRUE, calculate the transposition earlier with zm.transpose, or
    // move around the order of operations in the shader.
    gl.glUniformMatrix4fv(app.shader_program.getUniformLocation("transform"), 1, gl.GL_TRUE, &transform[0][0]);
    app.triangle.draw();

    return true;
}
