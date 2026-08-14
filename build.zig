pub fn build(b: *std.Build) void {
    var features = std.Target.Cpu.Feature.Set.empty;
    features.addFeature(@intFromEnum(std.Target.spirv.Feature.variable_pointers_storage_buffer));
    features.addFeature(@intFromEnum(std.Target.spirv.Feature.variable_pointers));
    const spirv_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv32,
        .os_tag = .vulkan,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        // .cpu_features_add = features,
    });

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const mod = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("main.zig"),
    });
    mod.addAnonymousImport("shader.spv", .{
        .root_source_file = compile_shader(b, spirv_target, .debug, b.path("shader.zig"), "shader.spv"),
    });

    const vulkan_path = b.graph.cwdRelativePath("C:/VulkanSDK/1.4.350.0/");
    const vulkan_include = vulkan_path.path(b, "Include/");
    const vulkan_lib = vulkan_path.path(b, "Lib");

    mod.linkSystemLibrary("vulkan-1", .{});
    mod.linkSystemLibrary("gdi32", .{});
    mod.addLibraryPath(vulkan_lib);
    mod.addSystemIncludePath(vulkan_include);

    const translate_c =  b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("c.h"),
    });
    translate_c.addIncludePath(vulkan_include);
    mod.addImport("c", translate_c.createModule());

    mod.addCSourceFile(.{
        .file = b.path("c.h"),
        .flags = &.{
            "-DRGFW_IMPLEMENTATION",
            "-DSTB_TRUETYPE_IMPLEMENTATION"
        },
        .language = .c,
    });

    const exe = b.addExecutable(.{
        .name = "pasim",
        .root_module = mod,
    });
    b.installArtifact(exe);
}

fn compile_shader(
    b: *std.Build,
    spirv_target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    src: std.Build.LazyPath,
    name: []const u8,
) std.Build.LazyPath {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = src,
            .target = spirv_target,
            .optimize = optimize,
        })
    });
    b.installArtifact(exe);
    return exe.getEmittedBin();
}

const std = @import("std");
