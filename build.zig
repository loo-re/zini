const std = @import("std");
const builder = @import("build_runner");

pub fn build(b: *std.Build) !void {
    const version = std.SemanticVersion{
        .major = 0,
        .minor = 1,
        .patch = 0,
    };
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zini_mod = b.addModule("zini", .{
        .root_source_file = b.path("src/zini.zig"),
        .target = target,
        .optimize = optimize,
    });

    const libDyn = b.addLibrary(.{
        .name = "zini", // Produit libmon_lib.so
        .root_module = zini_mod,
        .version = version,
        .linkage = .dynamic,
    });

    // Pour l'installation (facultatif)
    b.installArtifact(libDyn);

    const libStatic = b.addLibrary(.{
        .name = "zini", // Produit libmon_lib.so
        .root_module = zini_mod,
        .version = version,
        .linkage = .static,
    });

    // Pour l'installation (facultatif)
    b.installArtifact(libStatic);

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{ .root_module = zini_mod });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const example_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "example",
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

    // const docs_step = b.step("docs", "Generate docs.");
    // const install_docs = b.addInstallDirectory(.{
    //     .source_dir = tests.getEmittedDocs(),
    //     .install_dir = .prefix,
    //     .install_subdir = "docs",
    // });
    // docs_step.dependOn(&install_docs.step);

    // Étape optionnelle de génération de documentation
    // 👇 Étape personnalisée : appel de zig build-lib -femit-docs
    const docs_step = b.addSystemCommand(&[_][]const u8{
        "zig",          "build-lib",
        "src/zini.zig", "-femit-docs",
        "--name",       "zini",
        "-fno-emit-bin", // on veut juste la doc
    });

    b.step("docs", "Génère la documentation de la bibliothèque").dependOn(&docs_step.step);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_step);
    all_step.dependOn(example_step);
    all_step.dependOn(&docs_step.step);

    b.default_step.dependOn(all_step);
}
