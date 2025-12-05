const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common_mod = b.addModule("PClusterCommon", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/common/common.zig"),
    });

    // Compiling, installing and running the backend service.
    const backend_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/backend/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_exe_mod.addImport("PClusterCommon", common_mod);
    const backend_exe = b.addExecutable(.{
        .name = "PCluster_Backend",
        .root_module = backend_exe_mod,
        .use_llvm = false,
    });
    b.installArtifact(backend_exe);
    const run_backend_cmd = b.addRunArtifact(backend_exe);
    run_backend_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_backend_cmd.addArgs(args);
    }
    const run_backend_step = b.step("run_backend", "Run the backend");
    run_backend_step.dependOn(&run_backend_cmd.step);

    // UI dependencies
    const zclay_dep = b.dependency("zclay", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    // Compiling, installing and running the UI.
    const ui_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/ui/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    ui_exe_mod.addImport("raylib", raylib_dep.module("raylib"));
    ui_exe_mod.addImport("zclay", zclay_dep.module("zclay"));
    ui_exe_mod.addImport("PClusterCommon", common_mod);
    const ui_exe = b.addExecutable(.{
        .name = "PCluster_UI",
        .root_module = ui_exe_mod,
        .use_llvm = target.result.os.tag == .windows,
    });
    ui_exe.linkLibrary(raylib_dep.artifact("raylib"));
    b.installArtifact(ui_exe);
    const run_ui_cmd = b.addRunArtifact(ui_exe);
    run_ui_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_ui_cmd.addArgs(args);
    }
    const run_ui_step = b.step("run_ui", "Run the ui");
    run_ui_step.dependOn(&run_ui_cmd.step);

    // Compiling and running unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // A check step, it compiles everything but does not install it anywhere
    // this is used to quickly check for compilation errors.
    const check_backend_exe = b.addExecutable(.{ .name = "PCluster_Backend check", .root_module = backend_exe_mod, .use_llvm = false });
    const check_ui_exe = b.addExecutable(.{ .name = "PCluster_UI check", .root_module = ui_exe_mod, .use_llvm = false });

    const check_step = b.step("check", "Check that the files are compilable");
    check_step.dependOn(&check_backend_exe.step);
    check_step.dependOn(&check_ui_exe.step);
    check_step.dependOn(&unit_tests.step);
}
