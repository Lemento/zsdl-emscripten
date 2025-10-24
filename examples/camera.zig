const std = @import("std");

/// An interactive demo where the player can move around a textured cube using the arrow keys

pub fn build(b: *std.Build, src_path: []const u8, opt:anytype) *std.Build.Module
{
    // build core.zig as the module that has 'main' in it and return it
    const core_mod = b.createModule(.{
        .target = opt.target,
        .optimize = opt.optimize,
        .root_source_file = b.path("examples/core.zig"),
        .link_libc = true,
    });
    
    core_mod.addIncludePath(b.path("examples"));
    core_mod.addCSourceFile(.{ .file=b.path("examples/stb_image.c"), .flags=&.{ "-std=c89", "-Wall", }});

    { // Link Nuklear ui
        core_mod.addSystemIncludePath(b.dependency("sdl",.{}).path("include"));
    
        const nk_dep= b.dependency("Nuklear",.{});
        core_mod.addIncludePath(nk_dep.path(""));

        core_mod.addIncludePath(b.path("src/nuklear"));

        core_mod.addCSourceFile(.{.file=b.path("src/nuklear/nuklear_demo.c"), .flags=&.{ "-std=c99", "-Wall", "-Wno-format", "-fno-sanitize=undefined", }});
    }
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

const zm= @import("zmath");
const rad= std.math.degreesToRadians;
const deg= std.math.radiansToDegrees;

var gpa: core.Allocator= .init;

pub const App= struct
{
    window: core.InitResult= undefined,

    mainCamera: FPSCamera= .init(0.0,0.0,3.0, -90.0,0.0),
    press_up: bool= false,
    press_down: bool= false,
    press_left: bool= false,
    press_right: bool= false,

    shader_program: core.GLShader = undefined,
    shader_mvp: gl.GLint= undefined,
    cube: Object = undefined,
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

//* GUI */
fn update_ui(app: *const App) void
{
    const ctx= app.window.nkx;
    // TODO: Remove static open variable by replacing nk_begin with a function that passes the SourceLocation (@src) of where the function is called
    // This is because nk_begin keeps track of its windows using the file name/line macros where the function is called.
    const ui_win= struct
    { var open= true; };
    ui_win.open= (nk.nk_begin(app.window.nkx, "FPSCamera", nk.nk_rect(5, 5, 230, 100),
        nk.NK_WINDOW_BORDER|nk.NK_WINDOW_MOVABLE |
        nk.NK_WINDOW_MINIMIZABLE|nk.NK_WINDOW_TITLE) == 1);
    if(ui_win.open)
    {
        const cam= &app.mainCamera;

        nk.nk_layout_row_dynamic(ctx, 22.0, 1);
        nk.nk_labelf(ctx, nk.NK_TEXT_LEFT, "eyepos: %3.2f, %3.2f, %3.2f", cam.position[0], cam.position[1], cam.position[2]);
        nk.nk_labelf(ctx, nk.NK_TEXT_LEFT, "viewangle: %3.2f, %3.2f", deg(cam.yawRad), deg(cam.pitchRad));
    }
    nk.nk_end(ctx);
}

pub fn appInit(app: *App, system: core.InitResult) anyerror!void
{
    app.window= system;

    try app.glPool.init(gpa.allocator());
    errdefer app.glPool.deinit();

    mat_proj= zm.perspectiveFovRhGl(rad(45.0), app.window.aspectRatio(), 0.1, 100.0);

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("camera.vs"), };

    const fragment_shader_source = [_][*:0]const u8
    { GL_VERSION, @embedFile("texture.fs"), };

    app.shader_program = try app.glPool.genShader(&vertex_shader_source, &fragment_shader_source);

    app.shader_program.use();
    gl.glUniform1i(app.shader_program.getUniformLocation("diffuse"), 0);

    app.shader_mvp= app.shader_program.getUniformLocation("u_MVP");
    // Reminder that opengl uses column-major matrices while
    // zmath matrices are row-major, so in order for the math to stay 
    // consistent you either tell opengl to transpose it by sending
    // GL_TRUE, calculate the transposition earlier with zm.transpose, or
    // move around the order of operations in the shader.
    gl.glUniformMatrix4fv(app.shader_mvp, 1, gl.GL_TRUE, &zm.identity()[0][0]);
    std.log.debug("Press Arrow keys for camera controls (fps)",.{});

    // cube vertices
    const vCube= [_]f32
    { // cube
    // positions
        -0.5, -0.5, -0.5,  0.0, 0.0,
         0.5, -0.5, -0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 0.0,

        -0.5, -0.5,  0.5,  0.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 1.0,
        -0.5,  0.5,  0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,

        -0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5, -0.5,  1.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5,  0.5,  0.5,  1.0, 0.0,

         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5,  0.5,  0.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,

        -0.5, -0.5, -0.5,  0.0, 1.0,
         0.5, -0.5, -0.5,  1.0, 1.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,

        -0.5,  0.5, -0.5,  0.0, 1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,
        -0.5,  0.5,  0.5,  0.0, 0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,
    };
    const mCube= Mesh.create(.Textured, &vCube, &.{});
    app.cube= try Mesh.createObject(mCube, &app.glPool);

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

const nk= core.nuklear;
pub fn appIterate(app: *App) anyerror!bool
{
    const cam= &app.mainCamera;
    var travelSpeed: f32=0.0;
    if(app.press_up)
    { travelSpeed= 0.1; }
    else if(app.press_down)
    { travelSpeed=-0.1; }

    if(app.press_left)
    { cam.yawRad-=rad(1.0); }
    else if(app.press_right)
    { cam.yawRad+=rad(1.0); }

    cam.addFromDirection(travelSpeed);
    mat_view= cam.calcViewMatrix();
    mat_model= zm.translationV(zm.Vec{ 0.0,0.0,0.0,1.0 });

    // const mat_mvp= zm.mul(mat_model, zm.mul(mat_proj, mat_view));
    const mat_mvp= mat_mul(&.{mat_model, mat_view, mat_proj});

    update_ui(app);

    // enable depth buffer for 3d rendering
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    app.shader_program.use();
    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, app.texID);
    gl.glUniformMatrix4fv(app.shader_mvp, 1, gl.GL_TRUE, &mat_mvp[0][0]);
    app.cube.draw();

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

    ///calculate direction camera is facing and apply that direction as distance
    fn addFromDirection(cam: *FPSCamera, distance: f32) void
    {
      // clamp values of yawRad so that is always within 0-360 degrees
      // use @rem if we want to preserve sign
      cam.yawRad= @mod(cam.yawRad, 2.0*std.math.pi);
      // clamp values of pitchRad so that is is always within 180;
      cam.pitchRad= @mod(cam.pitchRad, (3.0*std.math.pi)/2.0);
      const displacement: zm.Vec= @splat(distance);
      const direction: zm.Vec= FPSCamera.updateDir(cam.yawRad, cam.pitchRad);

      cam.front= zm.normalize4 (direction);
      cam.position= zm.mulAdd (cam.front,displacement,cam.position);
    }

    fn calcViewMatrix(cam: *FPSCamera) zm.Mat
    {
      return zm.lookAtRh
        (cam.position,cam.position+cam.front,up);
    }
};
