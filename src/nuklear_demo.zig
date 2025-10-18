const std= @import("std");
const c_flags= &.{ "-Wall", "-Wno-format", "-fno-sanitize=undefined" };

pub fn build(b: *std.Build, _: anytype, opt: anytype) *std.Build.Module
{
    const app_mod= b.createModule(.{
        .root_source_file= null,
        .target=opt.target, .optimize=opt.optimize,
        .link_libc= true,
    });

    app_mod.addSystemIncludePath(b.dependency("sdl",.{}).path("include"));
    app_mod.addCSourceFile(.{.file=b.path("src/nuklear/main.c"), .flags=c_flags});
    app_mod.addIncludePath(b.path("src/nuklear"));
    
    const nk_dep= b.dependency("Nuklear",.{});
    app_mod.addIncludePath(nk_dep.path(""));

    return app_mod;
}