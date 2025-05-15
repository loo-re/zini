const std = @import("std");
const builder = @import("build_runner");
const VERSION = @import("./src/zini.zig").VERSION;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const zini_mod = b.addModule("zini", .{
        .root_source_file = b.path("src/zini.zig"),
        .target = target,
        .optimize = optimize,
    });

    // LIBRARY

    const libDyn = b.addLibrary(.{
        .name = "zini", // Produit libmon_lib.so
        .root_module = zini_mod,
        .version = VERSION,
        .linkage = .dynamic,
    });

    // Pour l'installation (facultatif)
    b.installArtifact(libDyn);

    const libStatic = b.addLibrary(.{
        .name = "zini", // Produit libmon_lib.so
        .root_module = zini_mod,
        .version = VERSION,
        .linkage = .static,
    });

    // Pour l'installation (facultatif)
    b.installArtifact(libStatic);

    // TESTS
    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{ .root_module = zini_mod });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // EXAMPLES
    const example_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "simple",
        "read",
        "server",
    }) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        const install_example = b.addInstallArtifact(example, .{});
        example.root_module.addImport("zini", zini_mod);
        example_step.dependOn(&example.step);
        example_step.dependOn(&install_example.step);
    }

    // DOCUMENTATION

    // Étape optionnelle de génération de documentation
    // 👇 Étape personnalisée : appel de zig build-lib -femit-docs
    const docs_step = b.addSystemCommand(&[_][]const u8{
        "zig",          "build-lib",
        "src/zini.zig", "-femit-docs",
        "--name",       "zini",
        "-fno-emit-bin", // on veut juste la doc
    });

    b.step("docs", "Génère la documentation de la bibliothèque").dependOn(&docs_step.step);

    // COMMANDE PAR DEFAUT (all)
    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_step);
    all_step.dependOn(example_step);
    all_step.dependOn(&docs_step.step);

    b.default_step.dependOn(all_step);
}
