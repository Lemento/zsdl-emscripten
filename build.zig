const std = @import("std");

const requested_browser = "chrome";

const SOURCES =struct
{
    pub const demo= @import("src/demo.zig");
    pub const demogl= @import("src/demogl.zig");
};

pub fn build(b: *std.Build) void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var system_include_path: ?std.Build.LazyPath = null;
    var lto: ?std.zig.LtoMode = null;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot == null) {

                // std.log.err("'--sysroot' is required when building for Emscripten", .{});
                // std.process.exit(1);
                
                const emsdk_path1 = emsdkPath(b);
                const emsdk_path = emsdk_path1[0..emsdk_path1.len-2];

                const emsdk_sysroot = b.pathJoin
                    (&.{ emsdk_path, "sysroot", });
                
                b.sysroot = emsdk_sysroot;
            }
            const emsdk_include = b.pathJoin(&.{ b.sysroot.?, "include" });
            system_include_path = .{ .cwd_relative = emsdk_include };

            if (optimize != .Debug) {
                lto = .full;
            }
        },
        else => {},
    }

    const options=.
    {
        .target=target, .optimize=optimize,
        .emsdk_include_path= system_include_path,
        .lto=lto
    };

    buildApp(b, "demo", options);
    buildApp(b, "demogl", options);
}

fn buildApp(b: *std.Build, comptime exe_name: []const u8, opt: anytype) void
{
    const src_path= "src/"++exe_name++".zig";

    const app_mod = b.createModule(.{
        .target = opt.target,
        .optimize = opt.optimize,
        .root_source_file = b.path("src/main.zig"),
        .link_libc = true,
    });

    if (opt.target.result.os.tag == .windows and opt.target.result.abi == .msvc) {
        // Work around a problematic definition in wchar.h in Windows SDK version 10.0.26100.0
        app_mod.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }
    if (opt.emsdk_include_path) |path| {
        app_mod.addSystemIncludePath(path);
    }

    // No matter the exe name, it will be imported to main as a 'impl' module as it implements the app functions that main defines.
    const impl_mod = b.createModule(.{
        .root_source_file = b.path(src_path),
        .target=opt.target, .optimize=opt.optimize,
        .link_libc=true,
    });

    const os_tag = opt.target.result.os.tag;
    if(os_tag != .emscripten and os_tag != .wasi)
    {
        app_mod.addIncludePath(b.path("glad/include"));
        app_mod.addCSourceFile(.{ .file=b.path("glad/src/glad.c"), .flags=&.{ "-fno-sanitize=undefined" }});
    }

    impl_mod.addImport("main", app_mod);
    app_mod.addImport("impl", impl_mod);

    const sdl_dep = b.dependency("sdl", .{
        .target = opt.target,
        .optimize = opt.optimize,
        .lto = opt.lto,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    const run = b.step("run-"++exe_name, "Run '"++exe_name++"' program");

    if (opt.target.result.os.tag == .emscripten) {
        // Build for the Web.

        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = exe_name,
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
        }

        run_emcc.addArg("-sMIN_WEBGL_VERSION=2");
        run_emcc.addArg("-sMAX_WEBGL_VERSION=2");

        // run_emcc.addArg("-sNO_FILESYSTEM=1");
        run_emcc.addArg("-sMALLOC='emmalloc'");

        run_emcc.addArg("-sGL_ENABLE_GET_PROC_ADDRESS=1");
        run_emcc.addArg("-sINITIAL_MEMORY=64Mb");
        run_emcc.addArg("-sSTACK_SIZE=16Mb");

        // run_emcc.addArg("-sFULL-ES3=1");
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
        const app_html = run_emcc.addOutputFileArg(exe_name++".html");

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", exe_name++".html",  }));
        
        run_emrun.addArg("--browser="++requested_browser);
        // if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(b.getInstallStep());

        run.dependOn(&run_emrun.step);

    } else {
        // Build for desktop.
        const app_exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = app_mod,
        });
        app_exe.lto = opt.lto;
        b.installArtifact(app_exe);

        const run_app = b.addRunArtifact(app_exe);
        if (b.args) |args| run_app.addArgs(args);
        run_app.step.dependOn(b.getInstallStep());

        run.dependOn(&run_app.step);
    }
}

inline fn emsdkPath(b: *std.Build) []const u8 {
    // const emsdk = b.dependency("emsdk", .{});
    // const emsdk_path = emsdk.path("").getPath(b);
    // return emsdk_path;

    // const emsdk = std.fs.path.join(b.allocator,
    // &.{ "emsdk" })
    // catch unreachable;

    // return "C:\\Users\\Dagai\\Desktop\\zig-examples\\demo\\emsdk\\upstream\\emscripten\\cache";
    return b.run(&.{ "em-config", "CACHE" });
}
