pub const PARTICLE_SIZE = 0.05;
pub const PARTICLE_KERNEL_SIZE = 0.01;
pub const Vertex = struct {
    const positions = [driver.VERT_PER_PARTICLE]V2 {
        .{-0.5, -0.5}, 
        .{0.5, 0.5},
        .{-0.5, 0.5},
        .{-0.5, -0.5}, 
        .{0.5, -0.5},
        .{0.5, 0.5}
    };

    // const pos = @extern(*addrspace(.input) V2, .{
    //     .name = "pos",
    //     .decoration = .{ .location = 0 },
    // });
    // const color = @extern(*addrspace(.input) V3, .{
    //     .name = "color",
    //     .decoration = .{ .location = 1 },
    // });
    const particles = @extern(*addrspace(.storage_buffer) const ParticleArray , .{
        .name = "particles",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
    });

    const frag_color = @extern(*addrspace(.output) V3, .{
        .name = "frag_color",
        .decoration = .{ .location = 0 },
    });
    const frag_pos  = @extern(*addrspace(.output) V2, .{
        .name = "frag_pos",
        .decoration = .{ .location = 1 },
    });
    const center = @extern(*addrspace(.output) V2, .{
        .name = "center",
        .decoration = .{ .location = 2 },
    });

    fn main() callconv(.spirv_vertex) void {
        const constant = @extern(*addrspace(.push_constant) driver.Push_Constant, .{.name = "push_constant"}).*;
        const camera = constant.camera;

        const off_i = spirv.vertex_index % driver.VERT_PER_PARTICLE;
        const i = spirv.vertex_index / driver.VERT_PER_PARTICLE;

        const zoom = splat2(camera.zoom);
        center.* = (particles.ptr[i].pos + V2 {camera.pos[0],camera.pos[1]}) * zoom;
        const pos_offset = center.* + (positions[off_i] * splat2(PARTICLE_SIZE)) * splat2(camera.zoom);
        spirv.position_out.* = .{
            pos_offset[0], pos_offset[1], 0, 1
        };
        frag_pos.* = pos_offset;
        frag_color.* = particles.ptr[i].color;
    }
};

const Fragment = struct {
    const frag_color = @extern(*addrspace(.input) V3, .{
        .name = "frag_color",
        .decoration = .{ .location = 0 },
    });
    const frag_pos = @extern(*addrspace(.input) V2, .{
        .name = "frag_pos",
        .decoration = .{ .location = 1 },
    });
    const center = @extern(*addrspace(.input) V2, .{
        .name = "center",
        .decoration = .{ .location = 2 },
    });

    const out_color = @extern(*addrspace(.output) V4, .{
        .name = "out_color",
        .decoration = .{ .location = 0 },
    });

    fn main() callconv(.{ .spirv_fragment = .{ .depth_assumption = .greater } }) void {
        const constant = @extern(*addrspace(.push_constant) driver.Push_Constant, .{.name = "push_constant"}).*;
        const d = len(frag_pos.*-center.*);

        const glow_radius = PARTICLE_SIZE/2.0 * constant.camera.zoom;
        const kernel_radius = PARTICLE_KERNEL_SIZE/2.0 * constant.camera.zoom;

        var alpha: f32 = if (d < kernel_radius) 1 else 0;
        if (d < glow_radius) {
            alpha += 0.4*@exp((-d/kernel_radius)*1.5);
        } else {
            alpha = 0;
        }

        out_color.* = .{
            frag_color[0],
            frag_color[1],
            frag_color[2],
            alpha,
        };
    }
};

comptime {
    @export(&Vertex.main,   .{ .name = "vert" });
    @export(&Fragment.main, .{ .name = "frag" });
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

const std = @import("std");
const spirv = std.spirv;
const driver = @import("main.zig");

fn SpirvArray(comptime T: type) type {
    return extern struct {
        ptr: @SpirvType(.{ .runtime_array = T }),
    };
}
const ParticleArray = SpirvArray(driver.Particle);

pub fn dist2(a: V2, b: V2) f32 {
    return len2(a-b);
}

pub fn len(a: V2) f32 {
    return @sqrt(len2(a));
}

pub fn len2(a: V2) f32 {
    return @reduce(.Add, a*a);
}

pub fn splat2(a: f32) V2 {
    return @splat(a);
}
