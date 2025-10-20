// Here we define some defaults for all the apps
// Specifically libraries that need different headers if compiling to native vs web
const builtin = @import("builtin");

pub const PLATFORM =
    if(builtin.os.tag == .emscripten or builtin.os.tag == .wasi)
        .WEB else .NATIVE;

pub const sdl = @cImport
({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_opengl.h");
});
pub const stb_image= @cImport(@cInclude("stb_image.h"));

pub const gl =
    if(PLATFORM==.NATIVE)
        @cImport(@cInclude("glad/glad.h"))
    else
        @cImport(@cInclude("GLES3/gl3.h"));

const GLuint= gl.GLuint;

pub const emscripten= struct{
    pub const c= @cImport(if(PLATFORM==.WEB){ @cInclude("emscripten.h"); });

    pub const set_main_loop= c.emscripten_set_main_loop;
    pub const cancel_main_loop= c.emscripten_cancel_main_loop;
};

pub const GLShader= struct
{
    id:GLuint,

    pub inline fn use(program: GLShader) void
    { gl.glUseProgram(program.id); }

    pub inline fn getUniformLocation(program: GLShader, name: [*:0]const u8) gl.GLint
    { return gl.glGetUniformLocation(program.id, name); }
};

pub const GLPool = struct
{
    allocator: std.mem.Allocator,
    vaos: std.ArrayList(GLuint),
    buffers: std.ArrayList(GLuint),
    shaders: std.ArrayList(GLuint),
    textures: std.ArrayList(GLuint),

    pub const empty= GLPool{ .allocator=undefined, .vaos=.empty, .buffers=.empty, .shaders=.empty, .textures=.empty };

    pub fn init(pool: *GLPool, allocator: std.mem.Allocator) !void
    {
        pool.allocator = allocator;
        errdefer pool.deinit();

        try pool.vaos.ensureUnusedCapacity(allocator, 2);
        try pool.buffers.ensureUnusedCapacity(allocator, 8);
        try pool.shaders.ensureUnusedCapacity(allocator, 4);
        try pool.textures.ensureUnusedCapacity(allocator, 2);
    }

    pub fn deinit(pool: *GLPool) void
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

    pub fn genVAO(pool: *GLPool) !gl.GLuint
    {
        const nVAO= try pool.vaos.addOne(pool.allocator);
        gl.glGenVertexArrays(1, nVAO);

        return nVAO.*;
    }

    pub fn genBuffer(pool: *GLPool) !gl.GLuint
    {
        const nBuffer= try pool.buffers.addOne(pool.allocator);
        gl.glGenBuffers(1, nBuffer);
        
        return nBuffer.*;
    }

    pub fn genShader(pool: *GLPool, vertShaderSrc: []const[*:0]const u8, fragShaderSrc: []const[*:0]const u8) !GLShader
    {
        const nShader = try pool.shaders.addOne(pool.allocator);
        nShader.* = try loadShaderFromSource(vertShaderSrc, fragShaderSrc);
        return .{.id=nShader.*};
    }

    pub fn genTexture(pool: *GLPool) !GLuint
    {
        const nTexture= try pool.textures.addOne(pool.allocator);
        gl.glGenTextures(1, nTexture);

        return nTexture.*;
    }
};

const Vertex= enum{ OnlyPosition, PosAndColor, Textured, };

pub const Mesh= struct
{
    vertexType: Vertex,
    vertexStride: u8,
    lenVertices: u31,
    ptrVertices: [*]const f32,
    elements: []const u32,

    pub const create= createMesh;
    pub const Object= RenderObject;
    pub const createObject= createRenderObject;

    pub fn sizeOfVertices(m: Mesh) i32
    { return m.vertexStride*m.lenVertices*@sizeOf(f32); }
    pub fn enableVertexAttributes(m: Mesh) void
    {
        const v_stride:i32= @as(i32, m.vertexStride)*@sizeOf(f32);
        switch(m.vertexType)
        {
            .OnlyPosition=>
            {
                gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, v_stride, null);
                gl.glEnableVertexAttribArray(0);
            },
            .PosAndColor=>
            {
                gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, v_stride, null);
                gl.glEnableVertexAttribArray(0);
                gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, v_stride, @ptrFromInt(3*@sizeOf(f32)));
                gl.glEnableVertexAttribArray(1);
            },
            .Textured=>
            {
                gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, v_stride, null);
                gl.glEnableVertexAttribArray(0);
                gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, v_stride, @ptrFromInt(3*@sizeOf(f32)));
                gl.glEnableVertexAttribArray(1);
            },
        }
    }
};

fn createMesh(vType: Vertex, vertices: []const f32, elements: []const u32) Mesh
{
    if(vertices.len == 0) @panic("No vertices passed!");

    const v_stride:u8= switch(vType)
    {
        .OnlyPosition=> 3,
        .PosAndColor=> 6,
        .Textured=> 5,
        // else => true,
    };

    if((vertices.len%v_stride != 0))
        @panic("Invalid length vertices!");

    return Mesh
    {
        .vertexType = vType,
        .vertexStride = v_stride,
        .lenVertices = @intCast(@divExact(vertices.len, v_stride)),
        .ptrVertices = vertices.ptr,
        .elements = elements
    };
}

const RenderObject= packed struct
{
    type: enum(u1){ Vertex, Element },
    vao: GLuint,
    len: u31,

    pub const draw= drawRenderObject;
};

fn createRenderObject(m: Mesh, pool: *GLPool) !RenderObject
{
    const nVAO: GLuint= try pool.genVAO();
    gl.glBindVertexArray(nVAO);
    defer gl.glBindVertexArray(0);

    const vbo: GLuint= try pool.genBuffer();
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, m.sizeOfVertices(), m.ptrVertices, gl.GL_STATIC_DRAW);

    m.enableVertexAttributes();

    if(m.elements.len > 0)
    {
        const ebo= try pool.genBuffer();
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32)*m.elements.len), m.elements.ptr, gl.GL_STATIC_DRAW);

        return RenderObject{ .type= .Element, .vao= nVAO, .len= @intCast(m.elements.len), };
    }

    return RenderObject
    {
      .type= .Vertex,
      .vao= nVAO,
      .len= m.lenVertices,
    };
}

pub fn drawRenderObject(obj: RenderObject) void
{
    gl.glBindVertexArray(obj.vao);
    switch(obj.type)
    {
        .Element=>
        {
            gl.glDrawElements(gl.GL_TRIANGLES, obj.len, gl.GL_UNSIGNED_INT, null);
        },
        .Vertex=>
        {
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, obj.len);
        },
    }
}

pub fn loadShaderFromSource(vertex_shader_source: []const [*:0]const u8, fragment_shader_source: []const [*:0]const u8) !gl.GLuint {
    const vertex_shader = try compileShader(vertex_shader_source, gl.GL_VERTEX_SHADER);
    defer gl.glDeleteShader(vertex_shader);

    const fragment_shader: GLuint = try compileShader(fragment_shader_source, gl.GL_FRAGMENT_SHADER);
    defer gl.glDeleteShader(fragment_shader);

    const shader_program = gl.glCreateProgram();
    errdefer gl.glDeleteProgram(shader_program);
    gl.glAttachShader(shader_program, vertex_shader);
    gl.glAttachShader(shader_program, fragment_shader);

    // Link the program
    gl.glLinkProgram(shader_program);

    var linked: i32 = undefined;
    gl.glGetProgramiv(shader_program, gl.GL_LINK_STATUS, &linked);
    if (linked == gl.GL_FALSE) {
        var info_len: i32 = 0;
        gl.glGetProgramiv(shader_program, gl.GL_INFO_LOG_LENGTH, &info_len);
        const static = struct {
            var buffer = std.mem.zeroes([255:0]u8);
        };
        gl.glGetProgramInfoLog(shader_program, info_len, null, &static.buffer);
        std.log.err("{s}", .{static.buffer});
        return error.FailureLinkingProgram;
    }

    return shader_program;
}

pub fn compileShader(shader_source: []const [*:0]const u8, shaderType: u32) !u32 {
    const program: GLuint = gl.glCreateShader(shaderType);
    gl.glShaderSource(program, @intCast(shader_source.len), @ptrCast(@alignCast(shader_source.ptr)), null);
    gl.glCompileShader(program);
    errdefer gl.glDeleteShader(program);

    var status: i32 = undefined;
    gl.glGetShaderiv(program, gl.GL_COMPILE_STATUS, &status);

    if (status == gl.GL_FALSE) {
        var info_len: i32 = 0;
        gl.glGetShaderiv(program, gl.GL_INFO_LOG_LENGTH, &info_len);
        const static = struct {
            var buffer = std.mem.zeroes([255:0]u8);
        };
        gl.glGetShaderInfoLog(program, info_len, null, &static.buffer);
        std.log.err("{s}", .{static.buffer[0.. :0]});
        return error.FailedToCompileShader;
    }

    return program;
}

pub const InitResult= struct
{
    pub const Error= error{SDL};
    win: *sdl.SDL_Window,
    win_width: u32,
    win_height: u32,
    glx: sdl.SDL_GLContext,

    pub fn show(this: InitResult) Error!void
    {
        if(sdl.SDL_ShowWindow(this.win) == false)
        { return error.SDL; }
    }

    pub fn refresh(this: InitResult) Error!void
    {
        if(sdl.SDL_GL_SwapWindow(this.win) == false)
        { return error.SDL; }
    }

    pub fn aspectRatio(this: InitResult) f32
    { return @as(f32, @floatFromInt(this.win_width)) / @as(f32, @floatFromInt(this.win_height)); }
};

pub const InitOptions= struct
{
    title: [*:0]const u8= "untitled",
    width: u31, height: u31,

    /// Sets the starting background color for the window
    /// 
    /// By default, the color is a dull blue to make certain that SDL_GL functions are working
    /// 
    /// Omits the 'alpha' parameter in glClearColor
    bgColor: std.meta.Tuple(&.{f32,f32,f32})= .{0.4, 0.6, 0.8},
    /// Sets vsync. If 0, turns off vsync,
    setVSync: ?i32= null,
};

/// Setup SDL and OpenGL systems/contexts, pass handles to app.init.
/// 
/// Reminder that SDL_Window is set to hidden by default because I'm a crazy person and I like it when the window opens once the scene is ready to be drawn.
fn setup(opt: InitOptions) InitResult.Error!InitResult
{
    // Initialize SDL systems
    if(sdl.SDL_Init(sdl.SDL_INIT_VIDEO) == false)
    {
        std.log.err("Failed to initialize SDL", .{});
        return error.SDL;
    }
    errdefer sdl.SDL_Quit();

    const flags= sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_OPENGL;
    const win = sdl.SDL_CreateWindow(opt.title, opt.width, opt.height, flags)
    orelse
    {
        std.log.err("Failed to create SDL_Window", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyWindow(win);

    // setup gl
    const gl_ctx= sdl.SDL_GL_CreateContext(win)
    orelse
    {
        std.log.err("Failed to create OpenGL context",.{});
        return error.SDL;
    };
    errdefer{ _=sdl.SDL_GL_DestroyContext(gl_ctx); }

    // On web gl functions are given from emscripten
    if(PLATFORM==.NATIVE)
    { _=gl.gladLoadGLLoader(@ptrCast(&sdl.SDL_GL_GetProcAddress)); }

    if(sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_ES) == false)
    { std.log.err("Failed to set context profile!",.{}); }
    if(sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1) == false)
    { std.log.err("Failed to set doublebuffer!",.{}); }
    @call(.auto, gl.glClearColor, opt.bgColor++.{1.0});
    
    if(opt.setVSync) |interval|
    {
        if(sdl.SDL_GL_SetSwapInterval(interval) == false)
        { std.log.err("Failed to set VSync!",.{}); }
    }

    gl.glViewport(0, 0, opt.width, opt.height);

    return .{ .win=win, .win_width= opt.width, .win_height= opt.height, .glx = gl_ctx, };
}

fn cleanup() void
{
    const gl_ctx= app_system.?.glx;
    const sdl_win= app_system.?.win;
    app_system= null;

    _=sdl.SDL_GL_DestroyContext(gl_ctx);
    sdl.SDL_DestroyWindow(sdl_win);
    sdl.SDL_Quit();
}

const std = @import("std");
const panic= std.debug.panic;
const assert= std.debug.assert;

pub const EventFlag= enum{ pass, stop };
const App = @import("impl").App;
comptime // A quick little interface enforcement checked at compile time
{
    assert(@TypeOf(@field(App, "init")) == fn(*App, InitResult) anyerror!void);
    assert(@TypeOf(@field(App, "quit")) == fn(*App) void);
    assert(@TypeOf(@field(App, "event")) == fn(*App, sdl.SDL_Event) EventFlag);
    assert(@TypeOf(@field(App, "iterate")) == fn(*App) anyerror!bool);
}
const app_setup: InitOptions= App.setup;
var app_status: ?anyerror= null;
var app_system: ?InitResult= null;
var app= App{};

const EmptyAllocator= struct
{
    pub const init=EmptyAllocator{};
    pub inline fn allocator(_: EmptyAllocator) std.mem.Allocator
    { return std.heap.c_allocator; }
    pub fn deinit(_: EmptyAllocator) void{}
};
pub const Allocator=
    if(PLATFORM==.NATIVE) std.heap.GeneralPurposeAllocator(.{})
    else EmptyAllocator;

pub fn main() void
{
    app_system= setup(app_setup)
    catch |err|
    {
        switch(err)
        {
          error.SDL=> panic("SDL: {s}", .{sdl.SDL_GetError()}), 
        //   else=> panic("{s}",.{@errorName(err)}),
        }
    };
    app.init(app_system.?) catch |err| { app_status=err; };

    if(PLATFORM==.WEB)
    { emscripten.set_main_loop(mainLoop, 0, true); }
    else
    { while(true){ mainLoop(); } }
}

fn mainLoop() callconv(.c) void
{
    if(app_status) |status|
    {
        switch(status)
        {
            error.RuntimeRequestQuit=>{},
            error.SDL=> panic("SDL: {s}", .{sdl.SDL_GetError()}),
            else=> panic("{s}", .{@errorName(status)}),
        }

        // Have the app remove its own resources first
        app.quit(); app= undefined;
        // Then cleanup sdl and opengl stuff declared at setup
        cleanup();
        
        if(PLATFORM==.WEB)
        { emscripten.cancel_main_loop(); }
        else
        { std.process.exit(0); }
    }

    var event: sdl.SDL_Event= undefined;
    while(sdl.SDL_PollEvent(&event))
    { if(app.event(event) == .stop){ app_status= error.RuntimeRequestQuit; } }
    
    // Check if iterate wants to continue to drawing frame
    if(app.iterate()) |drawFrame|
    { if(drawFrame == false) return; }

    // Or if it returned an error
    else |err|
    { app_status=err; }

    if(sdl.SDL_GL_SwapWindow(app_system.?.win) == false)
    { app_status= error.SDL; }
}
