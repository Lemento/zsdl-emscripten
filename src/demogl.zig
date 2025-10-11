const std = @import("std");

const APP = @import("app.zig").PLATFORM;
const sdl = @import("app.zig").sdl;
const gl = @import("app.zig").gl;
const em = @import("app.zig").em;

/// Make an example demo that opens a window with the Zig Logo
/// Uses SDL3 and OpenGL

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
        else { std.process.exit(0); }
    }

    var event: sdl.SDL_Event= undefined;
    while(sdl.SDL_PollEvent(&event))
    {
        impl.appEvent(&event) catch {quit=true;};
    }
    
    _=impl.appIterate();
}

const impl= struct{

var screen: *sdl.SDL_Window= undefined;
var gl_context: sdl.SDL_GLContext= undefined;
var img_surface: *sdl.SDL_Surface= undefined;
var shader_program: u32 = undefined;
var vertex_array_object: u32 = undefined;
var texture_id: u32 = undefined;

fn appInit() !void
{
    // Initialize SDL systems
    if(sdl.SDL_Init(sdl.SDL_INIT_VIDEO) == false)
    {
        std.log.err("Failed to initialize SDL", .{});
        return error.SDL;
    }
    errdefer sdl.SDL_Quit();
    std.log.debug("Initialized SDL!", .{});

    screen = sdl.SDL_CreateWindow("sdl2-zig-demo", 400, 140, sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_OPENGL) orelse
    {
        std.log.err("Failed to create SDL_Window", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyWindow(screen);

    // setup gl
    gl_context = sdl.SDL_GL_CreateContext(screen)
    orelse return error.SDL;
    errdefer{ _=sdl.SDL_GL_DestroyContext(gl_context); }

    if(APP==.NATIVE){ _=gl.gladLoadGLLoader(@ptrCast(&sdl.SDL_GL_GetProcAddress)); }

    gl.glClearColor(1.0, 1.0, 1.0, 1.0);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_ES);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DOUBLEBUFFER, 1);
    _=sdl.SDL_GL_SetSwapInterval(-1);

    gl.glViewport(0, 0, 400, 140);

    const GL_VERSION= "#version 300 es\n";
    const vertex_shader_source = [_][*:0]const u8
    {
        GL_VERSION,
        \\layout (location = 0) in vec4 aPosition;
        \\layout (location = 1) in vec2 aTexCoord;
        \\
        \\out vec2 vTexCoord;
        \\
        \\void main(){ gl_Position = aPosition; vTexCoord = aTexCoord; }
    };

    const fragment_shader_source = [_][*:0]const u8
    {
        GL_VERSION,
        \\precision mediump float;
        \\in vec2 vTexCoord;
        \\layout (location = 0) out vec4 fragColor;
        \\
        \\uniform sampler2D diffuse;
        \\
        \\void main(){ fragColor = texture(diffuse, vTexCoord); }
    };

    shader_program = try loadShaderFromSource(&vertex_shader_source, &fragment_shader_source);
    errdefer gl.glDeleteProgram(shader_program);

    // triangle vertices
    const vVertices= [_]f32
    {
        -1.0,  1.0, 0.0,  0.0, 0.0,
        -1.0, -1.0, 0.0,  0.0, 1.0,
         1.0, -1.0, 0.0,  1.0, 1.0,

        -1.0,  1.0, 0.0,  0.0, 0.0,
         1.0, -1.0, 0.0,  1.0, 1.0,
         1.0,  1.0, 0.0,  1.0, 0.0,
    };

    gl.glGenVertexArrays(1, &vertex_array_object);
    errdefer gl.glDeleteVertexArrays(1, &vertex_array_object);

    gl.glBindVertexArray(vertex_array_object);

    var vertex_pos_object: u32= undefined;
    gl.glGenBuffers(1, &vertex_pos_object);
    errdefer gl.glDeleteBuffers(1, &vertex_pos_object);

    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_pos_object);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vVertices)), &vVertices, gl.GL_STATIC_DRAW);

    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5*@sizeOf(f32), null);
    gl.glEnableVertexAttribArray(0);

    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5*@sizeOf(f32), @ptrFromInt(3*@sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);

    // Load assets
    const zig_bmp = @embedFile("zig.bmp");
    const rw = sdl.SDL_IOFromConstMem(zig_bmp, zig_bmp.len) orelse {
        std.log.err("Unable to get '{s}' with IOFromConstMem", .{"zig_bmp"});
        return error.SDL;
    };

    img_surface = sdl.SDL_LoadBMP_IO(rw, true)
    orelse
    {
        std.log.err("Failed to create SDL_Surface", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroySurface(img_surface);

    texture_id = createTextureFromSDLSurface(img_surface);
    errdefer gl.glDeleteTextures(1, &texture_id);

    _=sdl.SDL_ShowWindow(screen);
}


fn appQuit() void
{
    std.log.debug("Cleaning Up!", .{});

    // {
    //     if(err == error.SDL)
    //     { sdl.SDL_Log("SDL: %s\n", sdl.SDL_GetError()); }
    //     else
    //         std.log.err("{s}", .{@errorName(err)});
        
    //     // Return early on error since the following expects a full initialization.
    //     // If an error is thrown during initialization, cleanup would have already been executed by errdefer guards.
    //     return;
    // };

    sdl.SDL_DestroySurface(img_surface);
    sdl.SDL_DestroyWindow(screen);
    sdl.SDL_Quit();
}

fn appIterate() void
{
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
    gl.glUseProgram(shader_program);
    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture_id);
    gl.glUniform1i(gl.glGetUniformLocation(shader_program, "diffuse"), 0);
    gl.glBindVertexArray(vertex_array_object);
    gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);
    _=sdl.SDL_GL_SwapWindow(screen);
}

fn appEvent(event: *sdl.SDL_Event) !void
{
    switch(event.type)
    {
        sdl.SDL_EVENT_QUIT=> return error.RuntimeRequestedQuit,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(event.key.key == sdl.SDLK_ESCAPE)
            { return error.RuntimeRequestedQuit; }
        },
        else=>{},
    }
}
};


fn createTextureFromSDLSurface(original_surface: *sdl.SDL_Surface) gl.GLuint
{
    var new_texture: u32=undefined;
    gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);

    const w= 512; _=&w;// nearet power of two
    // _=original_surface;
    const converted_surface= SDL_CreateRGBSurface(original_surface.w, original_surface.h, 24, 0x0000_00ff, 0x0000_ff00, 0x00ff_0000, 0)
        orelse @panic("Failed to convert surface!");
    _=sdl.SDL_BlitSurface(original_surface, 0, converted_surface, 0);
    const pixels= [_]gl.GLubyte
    {
        0xff, 0x00, 0x00, // red
        0x00, 0xff, 0x00, // green
        0x00, 0x00, 0xff, // blue
        0xff, 0xff, 0x00, // yellow
    }; _=&pixels;

    gl.glGenTextures(1, &new_texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, new_texture);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGB, converted_surface.*.w, converted_surface.*.h, 0, gl.GL_RGB, gl.GL_UNSIGNED_BYTE, converted_surface.*.pixels.?);
    // c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGB, 2, 2, 0, c.GL_RGB, c.GL_UNSIGNED_BYTE, &pixels);

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);

    return new_texture;
}

fn SDL_CreateRGBSurface (width:i32, height:i32, depth:i32, Rmask:u32, Gmask:u32, Bmask:u32, Amask:u32) ?*sdl.SDL_Surface
{
    return sdl.SDL_CreateSurface(width, height,
            sdl.SDL_GetPixelFormatForMasks(depth, Rmask, Gmask, Bmask, Amask));
}


pub fn loadShaderFromSource(vertex_shader_source: []const [*:0]const u8, fragment_shader_source: []const [*:0]const u8) !u32 {
    const vertex_shader = try compileShader(vertex_shader_source, gl.GL_VERTEX_SHADER);
    defer gl.glDeleteShader(vertex_shader);

    const fragment_shader: u32 = try compileShader(fragment_shader_source, gl.GL_FRAGMENT_SHADER);
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

fn compileShader(shader_source: []const [*:0]const u8, shaderType: u32) !u32 {
    const program: u32 = gl.glCreateShader(shaderType);
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

