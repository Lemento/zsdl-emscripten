const std = @import("std");
const sdl = @import("main").sdl;
const APP = @import("main").PLATFORM;

/// Make an example demo that opens a window with the Zig Logo
/// Uses pure SDL3

pub const FN_IMPL= @import("main").AppStruct
{
    .init= sdlAppInit,
    .quit= sdlAppQuit,
    .event= sdlAppEvent,
    .iterate= sdlAppIterate,
};

var screen: *sdl.SDL_Window= undefined;
var renderer: *sdl.SDL_Renderer= undefined;
var img_surface: *sdl.SDL_Surface= undefined;
var img_texture: *sdl.SDL_Texture= undefined;

pub const os = if (@import("builtin").os.tag != .emscripten and @import("builtin").os.tag != .wasi) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};
fn sdlAppInit(_: ?*?*anyopaque, _: [][*:0]u8) !sdl.SDL_AppResult
{
    const mem = std.heap.c_allocator;
    // set current working directory
    if (APP==.WEB) {
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

    // Load a file from the /assets/ folder
    std.debug.print("Loading Assets...\n", .{});
    const asset_file = try std.fs.cwd().openFile("text_file.txt", .{});
    defer asset_file.close();
    const stat = try asset_file.stat();
    const text_file_contents = try asset_file.readToEndAlloc(mem, @intCast(stat.size));
    // NOTE(jae): 2024-02-24
    // Look in the Developer Console for your browser of choice, Chrome/Firefox and you should see
    // this printed on start-up.
    std.debug.print("text_file.txt({d}): {s}\n", .{ stat.size, text_file_contents });

    // Initialize SDL systems
    if(sdl.SDL_Init(sdl.SDL_INIT_VIDEO) == false)
    {
        std.log.err("Failed to initialize SDL", .{});
        return error.SDL;
    }
    errdefer sdl.SDL_Quit();
    std.log.debug("Initialized SDL!", .{});

    screen = sdl.SDL_CreateWindow("sdl2-zig-demo", 400, 140, sdl.SDL_WINDOW_HIDDEN) orelse
    {
        std.log.err("Failed to create SDL_Window", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyWindow(screen);

    renderer = sdl.SDL_CreateRenderer(screen, null)
    orelse
    {
        std.log.err("Failed to create SDL_Renderer", .{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyRenderer(renderer);

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

    img_texture = sdl.SDL_CreateTextureFromSurface(renderer, img_surface)
    orelse
    {
        std.log.err("Failed to create SDL_Texture from SDL_Surface",.{});
        return error.SDL;
    };
    errdefer sdl.SDL_DestroyTexture(img_texture);

    _=sdl.SDL_ShowWindow(screen);
    return sdl.SDL_APP_CONTINUE;
}

fn sdlAppQuit(_: ?*anyopaque, result: anyerror!sdl.SDL_AppResult) void
{
    std.log.debug("Cleaning Up!", .{});

    _=result catch |err|
    {
        if(err == error.SDL)
        { sdl.SDL_Log("SDL: %s\n", sdl.SDL_GetError()); }
        else
            std.log.err("{s}", .{@errorName(err)});
        
        // Return early on error since the following expects a full initialization.
        // If an error is thrown during initialization, cleanup would have already been executed by errdefer guards.
        return;
    };

    sdl.SDL_DestroyTexture(img_texture);
    sdl.SDL_DestroySurface(img_surface);
    sdl.SDL_DestroyRenderer(renderer);
    sdl.SDL_DestroyWindow(screen);
    sdl.SDL_Quit();
}

fn sdlAppIterate(_: ?*anyopaque) !sdl.SDL_AppResult
{
    _=sdl.SDL_RenderClear(renderer);
    _=sdl.SDL_RenderTexture(renderer, img_texture, null, null);
    _=sdl.SDL_RenderPresent(renderer);

    return sdl.SDL_APP_CONTINUE;
}

fn sdlAppEvent(_: ?*anyopaque, event: *sdl.SDL_Event) anyerror!sdl.SDL_AppResult
{
    switch(event.type)
    {
        sdl.SDL_EVENT_QUIT=> return sdl.SDL_APP_SUCCESS,
        sdl.SDL_EVENT_KEY_DOWN=>
        {
            if(event.key.key == sdl.SDLK_ESCAPE)
            { return sdl.SDL_APP_SUCCESS; }
        },
        else=>{},
    }

    return sdl.SDL_APP_CONTINUE;
}
