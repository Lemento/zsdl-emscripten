const std= @import("std");

pub fn build(b: *std.Build, _: anytype, opt: anytype) *std.Build.Module
{
    const app_mod= b.createModule(.{
        .root_source_file= b.path("src/nuklear_demo.zig"),
        .target=opt.target, .optimize=opt.optimize,
        .link_libc= true,
    });

    linkNuklear(app_mod, b);

    return app_mod;
}

const c_flags= [_][]const u8
{ "-std=c99", "-Wall", "-Wno-format", "-fno-sanitize=undefined", };
pub fn linkNuklear(app_mod: *std.Build.Module, b: *std.Build) void
{
    const sdl_dep= b.dependency("sdl",.{});
    app_mod.addSystemIncludePath(sdl_dep.path("include"));
    
    const nk_dep= b.dependency("Nuklear",.{});
    app_mod.addIncludePath(nk_dep.path(""));

    app_mod.addIncludePath(b.path("src/nuklear"));
    app_mod.addIncludePath(b.path("glad/include"));

    app_mod.addCSourceFile(.{.file=b.path("src/nuklear/nuklear_demo.c"), .flags=&c_flags});

}

const nuklear= @cImport(@cInclude("nuklear_demo.h"));
pub const c = nuklear;

pub fn main() !void
{
    _=nuklear.run();
}