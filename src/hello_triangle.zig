const std = @import("std");

const APP = @import("app.zig").PLATFORM;
const sdl = @import("app.zig").sdl;
const gl = @import("app.zig").gl;
const em = @import("app.zig").em;

/// Make an example demo that opens a window with a triangle built from vertices loaded to the gpu
/// Uses SDL3 and OpenGL
/// Create wrapper functions for sdl and opengl

// pub fn build(_: *std.Build.Module, _: *std.Build, _:anytype) void
// { }
var quit = false;
pub fn main() void
{
    impl.appInit() catch return;

    if(APP==.WEB)
    { em.set_main_loop(mainLoop, 0, true); }
    else
    { while(true){ mainLoop(); } }
}

fn mainLoop() callconv(.c) void
{
    if(quit)
    {
        impl.appQuit();
        
        if(APP==.WEB)
        { em.cancel_main_loop(); }
        else std.process.exit(0);
    }

    var event: sdl.SDL_Event= undefined;
    while(sdl.SDL_PollEvent(&event))
    { impl.appEvent(event) catch {quit=true;}; }
    
    impl.appIterate();
}

const impl=struct{

var screen: *sdl.SDL_Window= undefined;
var gl_ctx: sdl.SDL_GLContext= undefined;
var shader_program: u32 = undefined;
var triangle: RenderObject = undefined;
var square: RenderObject = undefined;
var display_obj: RenderObject = undefined;
var texture_id: u32 = undefined;
var glPool: GLPool= .empty;

const EmptyAllocator= struct
{
    const init=EmptyAllocator{};
    inline fn allocator(_: EmptyAllocator) std.mem.Allocator
    { return std.heap.c_allocator; }
    fn deinit(_: EmptyAllocator) void{}
};

var gpa: if(APP==.NATIVE) std.heap.GeneralPurposeAllocator(.{})
          else EmptyAllocator= .init;

fn appInit() !void
{
    std.log.debug("RenderObject({d})", .{@sizeOf(RenderObject)});
    try initSDLandOpenGL("hello_triangle", 600, 600);

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    {
        GL_VERSION,
        \\layout (location = 0) in vec3 aPos;
        \\
        \\void main(){ gl_Position = vec4(aPos, 1.0); }
    };

    const fragment_shader_source = [_][*:0]const u8
    {
        GL_VERSION,
        \\precision mediump float;
        \\layout (location = 0) out vec4 fragColor;
        \\
        \\void main(){ fragColor = vec4(1.0, 0.5, 0.2, 1.0); }
    };

    try glPool.init(gpa.allocator());
    errdefer glPool.deinit();

    shader_program = try glPool.genShader(&vertex_shader_source, &fragment_shader_source);

    // triangle vertices
    const vTriangle= [_]f32
    {
     -0.5, -0.5, 0.0,
      0.5, -0.5, 0.0,
      0.0,  0.5, 0.0,
    };

    triangle = try createRenderObject(&glPool, &vTriangle, &.{});
    display_obj = triangle;

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
    square = try createRenderObject(&glPool, &vSquare, &eSquare);

    // gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5*@sizeOf(f32), @ptrFromInt(3*@sizeOf(f32)));
    // gl.glEnableVertexAttribArray(1);

    // Load assets
    // const zig_bmp = @embedFile("zig.bmp");
    // const rw = sdl.SDL_IOFromConstMem(zig_bmp, zig_bmp.len) orelse {
    //     std.log.err("Unable to get '{s}' with IOFromConstMem", .{"zig_bmp"});
    //     return error.SDL;
    // };

    // const img_surface = sdl.SDL_LoadBMP_IO(rw, true)
    // orelse
    // {
    //     std.log.err("Failed to create SDL_Surface", .{});
    //     return error.SDL;
    // };
    // defer sdl.SDL_DestroySurface(img_surface);

    // texture_id = createTextureFromSDLSurface(img_surface);
    // errdefer gl.glDeleteTextures(1, &texture_id);

    _=sdl.SDL_ShowWindow(screen);
}

fn initSDLandOpenGL(title: [*:0]const u8, w: u31, h: u31) !void
{
    // Initialize SDL systems
    if(sdl.SDL_Init(sdl.SDL_INIT_VIDEO) == false)
    {
        std.log.err("Failed to initialize SDL", .{});
        return error.SDL;
    }
    errdefer sdl.SDL_Quit();
    std.log.debug("Initialized SDL!", .{});
    _=title;
    screen = sdl.SDL_CreateWindow("", w, h, sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_OPENGL)
    orelse
    {
        std.log.err("Failed to create SDL_Window", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyWindow(screen);

    // setup gl
    gl_ctx = sdl.SDL_GL_CreateContext(screen)
    orelse return error.SDL;
    errdefer{ _=sdl.SDL_GL_DestroyContext(gl_ctx); }

    // On web gl functions are given from emscripten
    if(APP==.NATIVE)
    {
        if(gl.gladLoadGLLoader(@ptrCast(&sdl.SDL_GL_GetProcAddress)) == 0)
        {
            std.log.err("GLAD: Failed to load GL Functions!", .{});
            return error.OpenGL;
        }
    }

    gl.glClearColor(0.4, 0.6, 0.8, 1.0);
    _=sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_ES);
    _=sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1);
    _=sdl.SDL_GL_SetSwapInterval(-1);

    gl.glViewport(0, 0, w, h);
}

fn appQuit() void
{
    std.log.debug("Cleaning Up!", .{});

    // _=result catch |err|
    // {
    //     if(err == error.SDL)
    //     { sdl.SDL_Log("SDL: %s\n", sdl.SDL_GetError()); }
    //     else
    //         std.log.err("{s}", .{@errorName(err)});
        
    //     // Return early on error since the following expects a full initialization.
    //     // If an error is thrown during initialization, cleanup would have already been executed by errdefer guards.
    //     return;
    // };

    defer
    {
        if(APP==.NATIVE)
        {
            if(gpa.deinit() == .leak)
            { std.testing.expect(false) catch @panic("MEMORY LEAK!"); }
        }
    }

    glPool.deinit();

    sdl.SDL_DestroyWindow(screen);
    _=sdl.SDL_GL_DestroyContext(gl_ctx);
    sdl.SDL_Quit();
}

fn appIterate() void
{
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
    gl.glUseProgram(shader_program);
    // gl.glActiveTexture(gl.GL_TEXTURE0);
    // gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
    // gl.glUniform1i(gl.glGetUniformLocation(shader_program, "diffuse"), 0);
    display_obj.draw();
    _=sdl.SDL_GL_SwapWindow(screen);
}

fn appEvent(evt: sdl.SDL_Event) !void
{
    switch(evt.type)
    {
        sdl.SDL_EVENT_QUIT=> return error.RuntimeRequestedQuit,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(evt.key.key == sdl.SDLK_ESCAPE)
            { return error.RuntimeRequestedQuit; }

            if(evt.key.key == sdl.SDLK_1)
            { display_obj= triangle; }
            if(evt.key.key == sdl.SDLK_2)
            { display_obj= square; }
        },
        else=>{},
    }
}
};

const RenderObject= packed struct
{
    type: enum(u1){ Vertex, Element },
    vao: u32,
    len: u31,

    fn draw(obj: RenderObject) void
    {
        switch(obj.type)
        {
            .Element=>
            {
                gl.glBindVertexArray(obj.vao);
                gl.glDrawElements(gl.GL_TRIANGLES, obj.len, gl.GL_UNSIGNED_INT, null);
            },
            .Vertex=>
            {
                gl.glBindVertexArray(obj.vao);
                gl.glDrawArrays(gl.GL_TRIANGLES, 0, obj.len);
            },
        }
    }
};

fn createRenderObject(pool: *GLPool, vertices: []const f32, elements: []const u32) !RenderObject
{
    if(vertices.len == 0){ @panic("No vertices passed!"); }
    if(vertices.len%3 != 0){ @panic("Vertices needs to be multiple of 3!"); }
 
    const nVAO = try pool.genVAO();
    gl.glBindVertexArray(nVAO);

    const vbo: u32= try pool.genBuffer();
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(@sizeOf(f32)*vertices.len), vertices.ptr, gl.GL_STATIC_DRAW);

    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3*@sizeOf(f32), null);
    gl.glEnableVertexAttribArray(0);

    if(elements.len > 0)
    {
        const ebo= try pool.genBuffer();
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32)*elements.len), elements.ptr, gl.GL_STATIC_DRAW);

        return RenderObject{ .type= .Element, .vao= nVAO, .len= @intCast(elements.len), };
    }

    return RenderObject{ .type= .Vertex, .vao= nVAO, .len= @intCast(vertices.len/3), };
}


const GLPool = struct
{
    allocator: std.mem.Allocator,
    vaos: std.ArrayList(gl.GLuint),
    buffers: std.ArrayList(gl.GLuint),
    shaders: std.ArrayList(gl.GLuint),
    textures: std.ArrayList(gl.GLuint),

    const empty= GLPool{ .allocator=undefined, .vaos=.empty, .buffers=.empty, .shaders=.empty, .textures=.empty };

    fn init(pool: *GLPool, allocator: std.mem.Allocator) !void
    {
        pool.allocator = allocator;
        errdefer pool.deinit();

        try pool.vaos.ensureUnusedCapacity(allocator, 2);
        try pool.buffers.ensureUnusedCapacity(allocator, 8);
        try pool.shaders.ensureUnusedCapacity(allocator, 4);
        try pool.textures.ensureUnusedCapacity(allocator, 2);
    }

    fn deinit(pool: *GLPool) void
    {
        if(pool.vaos.items.len > 0){ gl.glDeleteVertexArrays(@intCast(pool.vaos.items.len), pool.vaos.items.ptr); }
        pool.vaos.deinit(pool.allocator);

        if(pool.buffers.items.len > 0){ gl.glDeleteBuffers(@intCast(pool.buffers.items.len), pool.buffers.items.ptr); }
        pool.buffers.deinit(pool.allocator);

        for(pool.shaders.items) |program| { gl.glDeleteProgram(program); }
        pool.shaders.deinit(pool.allocator);

        if(pool.textures.items.len > 0){ gl.glDeleteTextures(@intCast(pool.textures.items.len), pool.textures.items.ptr); }
        pool.textures.deinit(pool.allocator);

        pool.* = undefined;
    }

    fn genVAO(pool: *GLPool) !gl.GLuint
    {
        const nVAO= try pool.vaos.addOne(pool.allocator);
        gl.glGenVertexArrays(1, nVAO);

        return nVAO.*;
    }

    fn genBuffer(pool: *GLPool) !gl.GLuint
    {
        const nBuffer= try pool.buffers.addOne(pool.allocator);
        gl.glGenBuffers(1, nBuffer);
        
        return nBuffer.*;
    }

    fn genShader(pool: *GLPool, vertShaderSrc: []const[*:0]const u8, fragShaderSrc: []const[*:0]const u8) !gl.GLuint
    {
        const nShader = try pool.shaders.addOne(pool.allocator);
        nShader.* = try @import("demogl.zig").loadShaderFromSource(vertShaderSrc, fragShaderSrc);
        return nShader.*;
    }
};


