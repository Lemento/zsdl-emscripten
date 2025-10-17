const std = @import("std");

// Set this to whatever browser you want to use
const requested_browser = "chrome";

const SOURCES =struct
{
    pub const demosdl= @import("src/demosdl.zig");
    pub const demogl= @import("src/demogl.zig");
    pub const nuklear_demo= @import("src/nuklear_demo.zig");
};

const EXAMPLES= struct {
    pub const hello_triangle= @import("examples/hello_triangle.zig");
    pub const transformations= @import("examples/transformations.zig");
    pub const textured= @import("examples/textured.zig");
};

pub fn build(b: *std.Build) void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var emsdk_include_path: ?std.Build.LazyPath = null;
    var lto: ?std.zig.LtoMode = null;
    switch (target.result.os.tag) {
        .emscripten => {
            emsdk_include_path = emsdkAddIncludePath(b);

            if (optimize != .Debug) {
                lto = .full;
            }
        },
        else => {},
    }
    const sdl_dep = b.dependency("sdl",.
    {
        .target = target,
        .optimize = optimize,
    });
    const options=.
    {
        .target=target, .optimize=optimize, .lto=lto,
        .sdl=sdl_dep, .emsdk_include_path=emsdk_include_path
    };

    // loops through SOURCES struct so that any source can be built and run with zig build run-app_name
    // Sources are only built if specified or run
    inline for(comptime std.meta.declarations(SOURCES)) |src|
    { buildApp(b, "src", src.name, @field(SOURCES, src.name), options); }

    inline for(comptime std.meta.declarations(EXAMPLES)) |src|
    { buildApp(b, "examples", src.name, @field(EXAMPLES, src.name), options); }
}

inline fn buildApp(b: *std.Build, dir: []const u8, app_name: []const u8, src: type, opt: anytype) void
{
    const src_path= dir++"/"++app_name++".zig";
    // std.log.debug("building for {s}", .{@typeName(@TypeOf(src))});

    // Let source specify its own build if specified. Otherwise build it as source by default
    const app_mod =
        if(@hasDecl(src, "build"))
            src.build(b, src_path, opt)
            
        else b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .root_source_file = b.path(src_path),
            .link_libc = true,
        });

    const os_tag = opt.target.result.os.tag;
    if (os_tag == .windows and opt.target.result.abi == .msvc) {
        // Work around a problematic definition in wchar.h in Windows SDK version 10.0.26100.0
        app_mod.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }

    if(os_tag != .emscripten and os_tag != .wasi)
    {
        app_mod.addIncludePath(b.path("glad/include"));
        app_mod.addCSourceFile(.{ .file=b.path("glad/src/glad.c"), .flags=&.{ "-fno-sanitize=undefined" }});
    }

    if (opt.emsdk_include_path) |path| {
        app_mod.addSystemIncludePath(path);
    }

    {
        var sdl_artifact= opt.sdl.artifact("SDL3");
        sdl_artifact.lto= opt.lto;
        app_mod.linkLibrary (sdl_artifact);
    }

    const run_name= "run-"++app_name;
    const run_step = b.step(run_name, "Run '"++app_name++"' program");

    if (opt.target.result.os.tag == .emscripten) {
        // Build for the Web.

        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = app_name,
            .root_module = app_mod,
        });
        app_lib.lto = opt.lto;

        const run_emcc = b.addSystemCommand(&.{"emcc"});

        // Pass 'app_lib' and any static libraries it links with as input files.
        // 'app_lib.getCompileDependencies()' will always return 'app_lib' as the first element.
        for (app_lib.getCompileDependencies(false)) |lib| {
            if (lib.isStaticLibrary()) {
                run_emcc.addArtifactArg(lib);
            }
        }

        if (opt.target.result.cpu.arch == .wasm64) {
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
        const app_html = run_emcc.addOutputFileArg(app_name++".html");

        const install_www= &b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step;
        // b.getInstallStep().dependOn(link_step);
        b.step(app_name, "Build '"++app_name++"' for desktop").dependOn(install_www);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", app_name++".html",  }));
        run_emrun.addArg("--browser="++requested_browser);
        // if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(install_www);

        run_step.dependOn(&run_emrun.step);

    } else {
        // Build for desktop.
        const app_exe = b.addExecutable(.{
            .name = app_name,
            .root_module = app_mod,
        });
        app_exe.lto = opt.lto;

        const install_exe= b.addInstallArtifact(app_exe, .{});

        const build_step= b.step(app_name, "Build '"++app_name++"' for desktop");
        build_step.dependOn(&install_exe.step);
        // build_step.dependOn(b.getInstallStep());
        // build_all_cmd.dependOn (&install_exe.step);

        const run_app = b.addRunArtifact(app_exe);
        // run_app.step.dependOn(b.getInstallStep());
        run_app.step.dependOn(&install_exe.step);
        if (b.args) |args| run_app.addArgs(args);

        run_step.dependOn(&run_app.step);
    }
}

fn emsdkAddIncludePath(b: *std.Build) std.Build.LazyPath
{
    if (b.sysroot == null) {
        // injest sysroot as commandline argument for emcc
        const emsdk_path1 = emsdkPath(b);
        const emsdk_path = emsdk_path1[0..emsdk_path1.len-2];

        const emsdk_sysroot = b.pathJoin(&.{ emsdk_path, "sysroot", });
                
        b.sysroot = emsdk_sysroot;
    }
    const emsdk_include = b.pathJoin(&.{ b.sysroot.?, "include" });

    return .{ .cwd_relative= emsdk_include };
}

inline fn emsdkPath(b: *std.Build) []const u8 {
    // const emsdk = b.dependency("emsdk", .{});
    // const emsdk_path = emsdk.path("").getPath(b);
    // return emsdk_path;

    // const emsdk = std.fs.path.join(b.allocator,
    // &.{ "emsdk" })
    // catch unreachable;

    return b.run(&.{ "em-config", "CACHE" });
}
