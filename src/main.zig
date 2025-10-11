const std = @import("std");
const builtin = @import("builtin");

// This file contains the main function and the structure for the sdl app that needs to be used to create an app.
// Those app functions are expected to be implemented in a seperate file and have this imported there.
// The implementation file must assign everything in there own AppStruct declaration that must be named 'FN_IMPL' so that this file can import and call them here.

pub const PLATFORM = if(builtin.os.tag == .emscripten or builtin.os.tag == .wasi) .WEB else .NATIVE;

pub const sdl = @cImport
({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// We include the glad opengl header files here and import them into the implementation files.
// Even though this file doesn't need them to build, it is linked with the wasm-emscripten library so it has access to the GLES3/egl.h header.
// Idk its just easier this way mannnnnnn.
pub const gl = @cImport
({
    if(PLATFORM==.NATIVE)
        @cInclude("glad/glad.h")
    else
    {
        @cInclude("GLES3/gl3.h");
        // @cInclude("EGL/egl.h");
        // @cInclude("EGL/eglext.h");
        // @cInclude("emscripten.h");
    }
});
const c = @cImport(
    if(PLATFORM==.WEB){ @cInclude("emscripten.h"); }
);

pub const std_options: std.Options = .{ .log_level = .debug, };

pub const AppStruct= struct
{
    init:fn(?*?*anyopaque,[][*:0]u8) anyerror!sdl.SDL_AppResult,
    quit:fn(?*anyopaque, anyerror!sdl.SDL_AppResult) void,
    event:fn(?*anyopaque, *sdl.SDL_Event) anyerror!sdl.SDL_AppResult,
    iterate:fn(?*anyopaque)anyerror!sdl.SDL_AppResult,
};
const sdl_app = @import("impl").FN_IMPL;

var app_err: ErrorStore = .{};
pub fn main() !u8 {
    app_err.reset();
    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(sdl.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));

    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return sdl.SDL_EnterAppMainCallbacks
    (argc, @ptrCast(argv),
     sdlAppInitC,
     sdlAppIterateC,
     sdlAppEventC,
     sdlAppQuitC
    );
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) sdl.SDL_AppResult {
    return sdl_app.init(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) sdl.SDL_AppResult {
    return sdl_app.iterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*sdl.SDL_Event) callconv(.c) sdl.SDL_AppResult {
    return sdl_app.event(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: sdl.SDL_AppResult) callconv(.c) void {
    sdl_app.quit(appstate, app_err.load() orelse result);
}

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: sdl.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = sdl.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) sdl.SDL_AppResult {
        if (sdl.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = sdl.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return sdl.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (sdl.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

//#endregion SDL main callbacks boilerplate

