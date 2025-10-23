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

const zm= @import("zmath");
const rad= std.math.degreesToRadians;
const deg= std.math.radiansToDegrees;

var gpa: core.Allocator= .init;

pub const App= struct
{
    window: core.InitResult= undefined,

    press_up: bool= false,
    press_down: bool= false,
    press_left: bool= false,
    press_right: bool= false,

    shader_program: core.GLShader = undefined,
    shader_mvp: gl.GLint= undefined,
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
    .title= "camera",
    .width= @intCast(WINDOW_WIDTH),
    .height= @intCast(WINDOW_HEIGHT),
    .setVSync= -1,
};

var mat_proj= zm.identity();
var mat_view= zm.identity();
var mat_model= zm.identity();

inline fn mat_mul(matrices: []const zm.Mat) zm.Mat
{
    var product: zm.Mat= zm.identity();
    for(matrices) |m|
    { product= zm.mul(product, m); }

    return product;
}

pub fn appInit(app: *App, system: core.InitResult) anyerror!void
{
    app.window= system;

    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("camera.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("basic.fs"), };

    app.shader_program = try app.glPool.genShader(&vertex_shader_source, &fragment_shader_source);

    mat_proj= zm.perspectiveFovRhGl(rad(45.0), app.window.aspectRatio(), 0.1, 100.0);

    // const mat_mvp= zm.mul(mat_model, zm.mul(mat_proj, mat_view));
    gl.glUseProgram(app.shader_program.id);
    app.shader_mvp= app.shader_program.getUniformLocation("u_MVP");
    // Reminder that opengl uses column-major matrices while
    // zmath matrices are row-major, so in order for the math to stay 
    // consistent you either tell opengl to transpose it by sending
    // GL_TRUE, calculate the transposition earlier with zm.transpose, or
    // move around the order of operations in the shader.
    gl.glUniformMatrix4fv(app.shader_mvp, 1, gl.GL_TRUE, &zm.identity()[0][0]);
    std.log.debug("Press Arrow keys for camera controls (fps)",.{});

    // triangle vertices
    const vTriangle= [_]f32
    {
    // positions
      1.0, -1.0, 0.0,
     -1.0, -1.0, 0.0,
      0.0,  1.0, 0.0,
    };
    const mTriangle= Mesh.create(.OnlyPosition, &vTriangle, &.{});
    app.triangle= try Mesh.createObject(mTriangle, &app.glPool);

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
        
            const pressed= (evt.type == sdl.SDL_EVENT_KEY_DOWN);
            switch(evt.key.key)
            {
                sdl.SDLK_UP=> app.press_up= pressed,
                sdl.SDLK_DOWN=> app.press_down= pressed,
                sdl.SDLK_LEFT=> app.press_left= pressed,
                sdl.SDLK_RIGHT=> app.press_right= pressed,
                else=>{},
            }
        },
        else=>{},
    }

    return .pass;
}

var mainCamera= FPSCamera.init(0.0,0.0,3.0,-90.0,0.0);

const nk= core.nuklear;
pub fn appIterate(app: *App) anyerror!bool
{
    var travelSpeed: f32=0.0;
    if(app.press_up)
    { travelSpeed= 0.1; }
    else if(app.press_down)
    { travelSpeed=-0.1; }

    if(app.press_left)
    { mainCamera.yawRad-=rad(1.0); }
    else if(app.press_right)
    { mainCamera.yawRad+=rad(1.0); }

    mainCamera.addFromDirection(travelSpeed);
    mat_view= mainCamera.calcViewMatrix();
    mat_model= zm.translationV(zm.Vec{ 0.0,0.0,0.0,1.0 });

    const mat_mvp= mat_mul(&.{mat_model, mat_view, mat_proj});

    //* GUI */
    const ctx= app.window.nkx;
    // TODO: Remove static open variable by replacing nk_begin with a function that passes the SourceLocation (@src) of where the function is called
    // This is because nk_begin keeps track of its windows using the file name/line macros where the function is called.
    const ui_win= struct
    { var open= true; };
    ui_win.open= (nk.nk_begin(app.window.nkx, "FPSCamera", nk.nk_rect(5, 5, 230, 250),
        nk.NK_WINDOW_BORDER|nk.NK_WINDOW_MOVABLE|nk.NK_WINDOW_SCALABLE |
        nk.NK_WINDOW_MINIMIZABLE|nk.NK_WINDOW_TITLE) == 1);
    if(ui_win.open)
    {
        nk.nk_layout_row_dynamic(ctx, 22.0, 1);
        nk.nk_labelf(ctx, nk.NK_TEXT_LEFT, "eyepos: %3.2f, %3.2f, %3.2f", mainCamera.position[0], mainCamera.position[1], mainCamera.position[2]);
        nk.nk_labelf(ctx, nk.NK_TEXT_LEFT, "viewangle: %3.2f, %3.2f", deg(mainCamera.yawRad), deg(mainCamera.pitchRad));
    }
    nk.nk_end(ctx);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    app.shader_program.use();
    gl.glUniformMatrix4fv(app.shader_mvp, 1, gl.GL_TRUE, &mat_mvp[0][0]);
    app.triangle.draw();

    return true;
}

const cos= std.math.cos;
const sin= std.math.sin;

const FPSCamera= struct
{
    position: zm.Vec,
    front: zm.Vec,
    yawRad: f32,
    pitchRad: f32,
    const up:zm.Vec= .{ 0.0,1.0,0.0,0.0 };

    fn init(x: f32, y:f32, z:f32, yawInDegrees: f32, pitchInDegrees: f32) FPSCamera
    {
      const yawRad:f32= rad(yawInDegrees);
      const pitchRad:f32= rad(pitchInDegrees);

      return FPSCamera{
        .position= .{ x, y, z, 1.0},
        .front= FPSCamera.updateDir(yawRad, pitchRad),
        .yawRad=yawRad, .pitchRad=pitchRad,
      };
    }

    fn updateDir(yawRad: f32, pitchRad: f32) zm.Vec
    {
      const dir= zm.Vec
      {
        cos(yawRad) * cos(pitchRad),
        sin(pitchRad),
        sin(yawRad) * cos(pitchRad),
        1.0,
      };
      return dir;
    }

    fn addFromDirection(cam: *FPSCamera, moveForward: f32) void
    {
      const displacement: zm.Vec= @splat(moveForward);
      const direction= FPSCamera.updateDir(cam.yawRad, cam.pitchRad);

      cam.front= zm.normalize4 (direction);
      cam.position= zm.mulAdd (cam.front,displacement,cam.position);
    }

    fn calcViewMatrix(cam: *FPSCamera) zm.Mat
    {
      return zm.lookAtRh
        (cam.position,cam.position+cam.front,up);
    }
};
