const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Registered before the lazy-dependency early return so the first
    // configure pass knows the options.
    const want_regen = b.option(
        bool,
        "regen",
        "Fetch the UCD and regenerate src/tables.zig",
    ) orelse false;
    const want_conformance = b.option(
        bool,
        "conformance",
        "Fetch the UCD and run the conformance tests",
    ) orelse false;
    const conformance_dir = b.option(
        []const u8,
        "conformance-dir",
        "Use a local UCD directory for the conformance tests",
    ) orelse "";

    // The one exported module. `src/tables.zig` is generated and committed,
    // so a consumer's build graph stops here.
    const mod = b.addModule("text", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (b.pkg_hash.len != 0) return;

    // testingx provides the test runner. It is lazy because only the root
    // build uses it.
    const testingx = b.lazyDependency("testingx", .{ .target = target }) orelse return;

    // The UCD is a lazy dependency. `regen` and `conformance` fetch it; a
    // normal build and a consumer never do.
    const needs_ucd = want_regen or (want_conformance and conformance_dir.len == 0);
    const ucd: ?*std.Build.Dependency = if (needs_ucd)
        b.lazyDependency("ucd", .{}) orelse return
    else
        null;

    // The conformance tests read their files at runtime. An empty path skips
    // them. `-Dconformance-dir` overrides the fetched release.
    const build_options = b.addOptions();
    if (conformance_dir.len != 0) {
        build_options.addOption([]const u8, "conformance_dir", conformance_dir);
    } else if (want_conformance) {
        build_options.addOptionPathDirectory("conformance_dir", ucd.?.path("."));
    } else {
        build_options.addOption([]const u8, "conformance_dir", "");
    }
    mod.addOptions("build_options", build_options);
    const runner: std.Build.Step.Compile.TestRunner = .{
        .path = testingx.path("src/runner.zig"),
        .mode = .simple,
    };

    const test_step = b.step("test", "Run the unit tests");

    const mod_tests = b.addTest(.{ .root_module = mod, .test_runner = runner });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    // The generator's parser tests. `just regen` runs the generator itself
    // against the UCD; the build never needs the data files.
    const gen_exe = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const gen_tests = b.addTest(.{
        .root_module = gen_exe.root_module,
        .test_runner = runner,
    });
    test_step.dependOn(&b.addRunArtifact(gen_tests).step);

    if (want_regen) {
        const gen = b.addRunArtifact(gen_exe);
        gen.setCwd(b.path("."));
        gen.addArg("--out");
        gen.addArg("src/tables.zig");
        gen.addDirectoryArg(ucd.?.path("."));
        const regen = b.step("regen", "Regenerate src/tables.zig from the pinned UCD");
        regen.dependOn(&gen.step);
    }
}
