const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The one exported module. `src/tables.zig` is generated and committed,
    // so a consumer's build graph stops here.
    const mod = b.addModule("text", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (b.pkg_hash.len != 0) return;

    // Both dependencies are lazy, so a consumer never fetches them. On the
    // first configure pass they are not fetched yet, and the build runner
    // fetches them and reruns this script.
    const testingx = b.lazyDependency("testingx", .{ .target = target }) orelse return;
    const runner: std.Build.Step.Compile.TestRunner = .{
        .path = testingx.path("src/runner.zig"),
        .mode = .simple,
    };

    const test_step = b.step("test", "Run the unit tests");

    const mod_tests = b.addTest(.{ .root_module = mod, .test_runner = runner });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    // The generator and the pinned UCD data are a maintainer step. `regen`
    // rewrites the committed table; `test` runs the generator's own tests.
    const ucd = b.lazyDependency("ucd", .{}) orelse return;
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

    const gen = b.addRunArtifact(gen_exe);
    gen.setCwd(b.path("."));
    gen.addArg("--out");
    gen.addArg("src/tables.zig");
    gen.addFileArg(ucd.path("UnicodeData.txt"));
    gen.addFileArg(ucd.path("DerivedCoreProperties.txt"));
    gen.addFileArg(ucd.path("PropList.txt"));
    const regen = b.step("regen", "Regenerate src/tables.zig from the pinned UCD release");
    regen.dependOn(&gen.step);
}
