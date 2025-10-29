const std = @import("std");

// Set this to whatever browser you want to use
const requested_browser = "chrome";

const SOURCES =struct
{
    pub const sdl_demo= @import("src/demosdl.zig");
    pub const opengl_demo= @import("src/demogl.zig");
    pub const nuklear_demo= @import("src/nuklear.zig");
};

const EXAMPLES= struct {
    pub const hello_triangle= @import("examples/hello_triangle.zig");
    pub const transforms= @import("examples/transforms.zig");
    pub const textured= @import("examples/textured.zig");
    pub const camera= @import("examples/camera.zig");
    pub const import= @import("examples/import3d.zig");
};

pub fn build(b: *std.Build) void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options=.
    { .target=target, .optimize=optimize, };

    // loops through SOURCES struct so that any source can be built and run with zig build run-app_name
    // Sources are only built if specified or run
    inline for(comptime std.meta.declarations(SOURCES)) |src|
    { buildApp(b, "src", src.name, @field(SOURCES, src.name), options); }

    inline for(comptime std.meta.declarations(EXAMPLES)) |src|
    { buildApp(b, "examples", src.name, @field(EXAMPLES, src.name), options); }
}

inline fn buildApp(b: *std.Build, dir: []const u8, app_name: []const u8, src: type, opt: anytype) void
{
    const src_name= comptime blk:
    {
      const name: []const u8= @typeName(src);
      for(name,0..) |c,i|
      { if(c == '.'){ break:blk name[i+1..]; }}
      break:blk name;
    };
    const src_path= comptime dir++"/"++src_name++".zig";
    // std.log.debug("building for {s}", .{@typeName(src)});

    const run_name= "run-"++app_name;
    const run_step = b.step(run_name, "Run '"++@typeName(src));

    // Let source runs its own build if specified. Otherwise build it as source by default
    const app_mod=
        if(@hasDecl(src, "build"))
            src.build(b, src_path, opt)
            
        else b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .root_source_file = b.path(src_path),
            .link_libc = true,
        });

    // Build for the Web.
    if (opt.target.result.os.tag == .emscripten) {
        run_step.dependOn
            (&buildWeb(b, src_name, app_mod, opt).step);

    // Build for native machine
    } else {
        run_step.dependOn
            (&buildExe(b, src_name, app_mod, opt).step);
    }
}

// Build for desktop.
inline fn buildExe(b: *std.Build, name: []const u8, root_module: *std.Build.Module, opt: anytype) *std.Build.Step.Run
{
    const os_tag = opt.target.result.os.tag;
    if (os_tag == .windows and opt.target.result.abi == .msvc) {
        // Work around a problematic definition in wchar.h in Windows SDK version 10.0.26100.0
        root_module.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }

    root_module.addIncludePath(b.path("glad/include"));
    root_module.addCSourceFile(.{ .file=b.path("glad/src/glad.c"), .flags=&.{ "-Wall", "-O3" }});
    const app_exe = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });

    const sdl_dep = b.dependency("sdl",.
    {
        .target = opt.target,
        .optimize = opt.optimize,
    });
    root_module.linkLibrary (sdl_dep.artifact("SDL3"));

    const install_exe= b.addInstallArtifact(app_exe, .{});

    const build_step= b.step(name, "Build '"++name++"' for desktop");
    build_step.dependOn(&install_exe.step);

    const run_app = b.addRunArtifact(app_exe);
    run_app.step.dependOn(&install_exe.step);
    if (b.args) |args| run_app.addArgs(args);

    return run_app;
}

inline fn buildWeb(b: *std.Build, name: []const u8, root_module: *std.Build.Module, opt: anytype) *std.Build.Step.Run
{
        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = name,
            .root_module = root_module,
        });
        var lto: ?std.zig.LtoMode = null;
        if (opt.optimize != .Debug) {
            lto = .full;
        }
        app_lib.lto= lto;
        app_lib.root_module.addSystemIncludePath(emsdkAddIncludePath(b));

        const sdl_dep = b.dependency("sdl",.
        {
            .target = opt.target,
            .optimize = opt.optimize,
            .lto=lto,
        });
        app_lib.root_module.linkLibrary (sdl_dep.artifact("SDL3"));

        const emcc_cmd=switch(builtin.target.os.tag)
            { .windows=> "emcc.bat", else=> "emcc" };
        const run_emcc = b.addSystemCommand
            (&.{b.pathJoin
              (&.{emsdkPath(b,"upstream/emscripten"), emcc_cmd })
            });

        // Pass 'app_lib' and any static libraries it links with as input files.
        // 'app_lib.getCompileDependencies()' will always return 'app_lib' as the first element.
        for (app_lib.getCompileDependencies(false)) |lib| {
            if (lib.isStaticLibrary()) {
                run_emcc.addArtifactArg(lib);
            }
        }

        if (opt.target.result.cpu.arch == .wasm64){
            run_emcc.addArg("-sMEMORY64");
        }

        run_emcc.addArgs(switch (opt.optimize) {
            .Debug => &.{
                "-O0",
                // Preserve DWARF debug information.
                "-g",
                // Use UBSan (full runtime).
                "-fsanitize=undefined",
            },
            .ReleaseSafe => &.{
                "-O3",
                // Use UBSan (minimal runtime).
                "-fsanitize=undefined",
                "-fsanitize-minimal-runtime",
            },
            .ReleaseFast => &.{
                "-O3",
            },
            .ReleaseSmall => &.{
                "-Oz",
            },
        });

        if (opt.optimize != .Debug) {
            // Perform link time optimization.
            run_emcc.addArg("-flto");
            // Minify JavaScript code.
            run_emcc.addArgs(&.{ "--closure", "1" });
            run_emcc.addArg("-sSTACK_OVERFLOW_CHECK=0");
            run_emcc.addArg("-sMALLOC='emmalloc'");
        } else {
            run_emcc.addArg("-sSTACK_OVERFLOW_CHECK=2");
            run_emcc.addArg("-sMALLOC='emmalloc-memvalidate'");
            run_emcc.addArg("-sSAFE_HEAP=1");
        }

        run_emcc.addArg("-sMIN_WEBGL_VERSION=2");
        run_emcc.addArg("-sMAX_WEBGL_VERSION=2");

        // run_emcc.addArg("-sNO_FILESYSTEM=1");

        run_emcc.addArg("-sGL_ENABLE_GET_PROC_ADDRESS=1");
        run_emcc.addArg("-sINITIAL_HEAP=64Mb");
        run_emcc.addArg("-sALLOW_MEMORY_GROWTH=1");
        run_emcc.addArg("-sSTACK_SIZE=32Kb");

        run_emcc.addArg("-sFULL-ES3=1");
        // run_emcc.addArg("-sUSE_GLFW=3");
        // run_emcc.addArg("-sASYNCIFY");
        // run_emcc.addArg("-sEXIT_RUNTIME");

        run_emcc.addArg("--embed-file");
        run_emcc.addArg("assets@/wasm_data");
        
        // Patch the default HTML shell.
        run_emcc.addArg("--pre-js");
        run_emcc.addFileArg(b.addWriteFiles().add("pre.js", (
            // Display messages printed to stderr.
            \\Module['printErr'] ??= Module['print'];
            \\
        )));

        run_emcc.addArg("-o");
        const app_html = run_emcc.addOutputFileArg(name++".html");

        const install_www= &b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step;
        b.step(name, "Build '"++name++"' for desktop").dependOn(install_www);

        const emsdk_cmd= switch(builtin.os.tag){ .windows=> "emsdk.bat", else=> "emsdk" };
        const emsdk_install= b.addSystemCommand(&.{ b.pathJoin(&.{ emsdkPath(b, ""), emsdk_cmd })});
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate= b.addSystemCommand(&.{ b.pathJoin(&.{ emsdkPath(b, ""), emsdk_cmd }) });
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);

        const emrun_cmd= switch(builtin.target.os.tag)
            { .windows=> "emrun.bat", else=> "emrun" };
        const run_emrun = b.addSystemCommand(&.{b.pathJoin
            (&.{ emsdkPath(b, "upstream/emscripten"), emrun_cmd })});
        run_emrun.addArg
            (b.pathJoin(&.{ b.install_path, "www", name++".html",  }));
        run_emrun.addArg("--browser="++requested_browser);
        // if (b.args) |args| run_emrun.addArgs(args);
        
        run_emrun.step.dependOn(&emsdk_activate.step);
        run_emrun.step.dependOn(install_www);

        return run_emrun;
}

const builtin= @import("builtin");

inline fn emsdkPath(b: *std.Build, sub_path: []const u8) []const u8
{ return b.dependency("emsdk",.{}).path(sub_path).getPath(b); }

fn emsdkAddIncludePath(b: *std.Build) std.Build.LazyPath
{
    if (b.sysroot == null) {
        // injest sysroot as commandline argument for emcc
        const emsdk_sysroot= b.pathJoin(&.{ emsdkPath(b, "upstream/emscripten/cache/sysroot") });
        b.sysroot = emsdk_sysroot;
    }
    const emsdk_include = b.pathJoin(&.{ b.sysroot.?, "include" });

    return .{ .cwd_relative= emsdk_include };
}