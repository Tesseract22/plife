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

    fn particle_quad() callconv(.spirv_vertex) void {
        const constant = @extern(*addrspace(.push_constant) driver.Particle_Constant, .{.name = "push_constant"});
        const particles1 = @extern(*addrspace(.storage_buffer) const Particle_Array , .{
            .name = "particles1",
            .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
        });
        const particles2 = @extern(*addrspace(.storage_buffer) const Particle_Array , .{
            .name = "particles2",
            .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
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


        const camera = constant.camera;

        const off_i = spirv.vertex_index % driver.VERT_PER_PARTICLE;
        const i = spirv.vertex_index / driver.VERT_PER_PARTICLE;

        const particle = if (constant.ping_pong) particles1.ptr[i] else particles2.ptr[i];

        const zoom = splat2(camera.zoom);
        center.* = (particle.pos + V2 {camera.pos[0],camera.pos[1]}) * zoom;
        const pos_offset = center.* + (positions[off_i] * splat2(PARTICLE_SIZE)) * splat2(camera.zoom);
        spirv.position_out.* = .{
            pos_offset[0], pos_offset[1], 0, 1
        };
        frag_pos.* = pos_offset;
        frag_color.* = constant.species[particle.specie].color;
    }

    fn triangle() callconv(.spirv_vertex) void {
        const pos = @extern(*addrspace(.input) V2, .{
            .name = "pos",
            .decoration = .{ .location = 0 },
        }).*;
        const color = @extern(*addrspace(.input) V4, .{
            .name = "color",
            .decoration = .{ .location = 1 },
        }).*;
        const in_tex_coord = @extern(*addrspace(.input) V2, .{
            .name = "in_tex_coord",
            .decoration = .{ .location = 2 },
        }).*;

        const tex_coord = @extern(*addrspace(.output) V2, .{
            .name = "tex_coord",
            .decoration = .{ .location = 0 },
        });
        const frag_color = @extern(*addrspace(.output) V4, .{
            .name = "frag_color",
            .decoration = .{ .location = 1 },
        });

        frag_color.* = color;

        tex_coord.* = in_tex_coord;
        const pos_offset = pos;
        spirv.position_out.* = .{
            pos_offset[0], pos_offset[1], 0, 1
        };
    }
};

const Fragment = struct {
    fn particle_quad() callconv(.{ .spirv_fragment = .{ .depth_assumption = .greater } }) void {
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

        const constant = @extern(*addrspace(.push_constant) driver.Particle_Constant, .{.name = "push_constant"}).*;
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
        // out_color.* = .{
        //     0,1,1,1
        // };
    }

    fn simple_tm(hdrColor: V3) V3 {
        return hdrColor / (hdrColor + splat3(1.0));
    }

    // adapted from https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
    fn aces_tm(x: V3) V3 {
        const a = splat3(2.51);
        const b = splat3(0.03);
        const c = splat3(2.43);
        const d = splat3(0.59);
        const e = splat3(0.14);
        return std.math.clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    fn exposure_tm(hdrColor: V3) V3 {
        const exposure = splat3(0.5);
        return splat3(1.0) - @exp(-hdrColor * exposure);
    }


    fn triangle() callconv(.{ .spirv_fragment = .{ .depth_assumption = .greater } }) void {
        const tex_coord = @extern(*addrspace(.input) V2, .{
            .name = "tex_coord",
            .decoration = .{ .location = 0 },
        }).*;
        const frag_color = @extern(*addrspace(.input) V4, .{
            .name = "frag_color",
            .decoration = .{ .location = 1 },
        }).*;

        const out_color = @extern(*addrspace(.output) V4, .{
            .name = "out_color",
            .decoration = .{ .location = 0 },
        });

        const sampled_image = @extern(*addrspace(.constant) const SampledImage, .{
            .name = "sampled_image",
            .decoration = .{
                .descriptor = .{
                    .set = 0,
                    .binding = 0,
                },
            },
        });
        const constant = @extern(*addrspace(.push_constant) vulkan.Triangle_Constant, .{.name = "push_constant"});

        if (constant.pure_color) {
            out_color.* = frag_color;
            return;
        }
        const hdr_color_a = frag_color * spirv.imageSampleImplicitLod(sampled_image, tex_coord);
        const hdr_color = V3 {hdr_color_a[0], hdr_color_a[1], hdr_color_a[2]};
        const mapped = simple_tm(hdr_color);
        // const gamma = 2.2;
        // inline for (0..3) |i|
        //     mapped[i] = std.math.pow(f32, mapped[i], 1.0 / gamma);
        out_color.* = .{mapped[0],mapped[1],mapped[2], hdr_color_a[3]};
    }
};

pub const Compute = struct {
    const constant = @extern(*addrspace(.push_constant) driver.Particle_Constant, .{.name = "push_constant"});

    pub fn linear_force(cfg: Force_Config, d: f32) f32 {
        const radius = cfg.radius;
        const strength = cfg.strength;
        const f = strength * @max(0, (radius-@abs(d)) / radius);
        return f;
    }

    fn compute_interaction(a: Particle, b: Particle) V2 {
        const l = @as(V2, a.pos) - b.pos;
        const d = len(l); // since we uses linear_force, zero distance does not cause infinite force
        const unit_l = if (d == 0) .{1,0} else l / splat2(d);
        // if (d > collision_max_dist) continue;
        const collision_force = linear_force(constant.collision_cfg, d);

        const interact_cfg_ab = constant.particle_force_configs[a.specie * constant.specie_ct + b.specie];
        const interact_force_ab = linear_force(interact_cfg_ab, d);

        // if (d == 0) {
        //     // const random_unit = get_random_unit_sphere(global_random);
        //     const random_unit = V2 {1,0};
        //     a.pos += random_unit * splat2(1e-3);
        //     b.pos -= random_unit * splat2(1e-3);
        // }
        return
            splat2(interact_force_ab) * unit_l
            + splat2(collision_force) * unit_l;

    }

    // TODO: make this configurable from CPU
    const PARTICLE_DRAG = 20;
    const boundary_mode: enum { clamp, wrap } = .wrap;

    const particles_in = @extern(*addrspace(.storage_buffer) Particle_Array , .{
        .name = "particles1",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
    });
    const particles_out = @extern(*addrspace(.storage_buffer) Particle_Array , .{
        .name = "particles2",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
    });
    const grid_offsets = @extern(*addrspace(.storage_buffer) U32_Array , .{
        .name = "grid_offsets",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } },
    });
    const grid_offsets_prefix = @extern(*addrspace(.storage_buffer) U32_Array , .{
        .name = "grid_offsets_prefix",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 3 } },
    });


    pub fn main() callconv(.{ .spirv_kernel = .{.x=driver.KERNEL_WORKGROUP_X,.y=1,.z=1}}) void {
        const dt = 1.0/60.0;
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;

        var spd = particles_in.ptr[i].spd;
        var pos = particles_in.ptr[i].pos;
        for (0..particles_in.ptr.len) |j| {
            if (i == j) continue;
            spd = spd + compute_interaction(particles_in.ptr[i], particles_in.ptr[j]) * splat2(dt);
        }
        pos = pos + splat2(dt) * spd;
        spd = spd * splat2(@exp(-PARTICLE_DRAG*dt*len(spd)));
        switch (boundary_mode) {
            .clamp => {
                if (pos[1] < -1) {
                    pos[1] = -1;
                    spd[1] = -spd[1];
                }
                if (pos[0] < -1) {
                    pos[0] = -1;
                    spd[0] = -spd[0];
                }
                if (pos[1] > 1.0) {
                    pos[1] = 1.0;
                    spd[1] = -spd[1];
                }
                if (pos[0] > 1) {
                    pos[0] = 1;
                    spd[0] = -spd[0];
                }
            },
            .wrap => {
                pos = @mod(pos + splat2(1), splat2(2)) - splat2(1);
            },
        }
        particles_out.ptr[i].spd = spd;
        particles_out.ptr[i].pos = pos;
    }

    pub const GRID_CELL_SIDE_COUNT = driver.GRID_CELL_SIDE_COUNT;
    pub const GRID_CELL_COUNT      = driver.GRID_CELL_COUNT;
    pub const GRID_CELL_SIZE       = driver.GRID_CELL_SIZE;


    pub fn cell_from_pos(pos: V2) @Vector(2, u32) {
        const x = std.math.clamp(pos[0], 0, 0.999999999);
        const y = std.math.clamp(pos[1], 0, 0.999999999);
        const bin_coord_f = V2{x,y} / splat2(GRID_CELL_SIZE);
        return @floor(bin_coord_f);
    }

    pub fn bin_from_cell(coord: [2]u32) u32 {
        return coord[1] * GRID_CELL_SIDE_COUNT + coord[0];
    }

    pub fn compute_grid_offsets() callconv(.{ .spirv_kernel = .{.x=driver.KERNEL_WORKGROUP_X,.y=1,.z=1}}) void {
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;
        const particle = particles_in.ptr[i];
        const cell = cell_from_pos(particle.pos);
        const bin = bin_from_cell(cell);

        // note: not yet supported in zig compiler
        // _ = @atomicRmw(u32, &grid_offsets.ptr[bin], .Add, 1, .monotonic);
        const sem = spirv.MemorySemantics {
        };
        _ = asm volatile (
            \\%ret = OpAtomicIAdd %t %ptr %scope %sem %val
            : [ret] "" (-> u32)
            : [t] "t" (u32),
              [ptr] "" (&grid_offsets.ptr[bin]),
              [scope] "" (@as(u32, @intFromEnum(spirv.Scope.device))),
              [sem] "" (@as(u32, @bitCast(sem))),
              [val] "i" (1),
        );
    }

    // TODO: parallelize this?
    pub fn compute_offset_prefix() callconv(.{ .spirv_kernel = .{.x=1,.y=1,.z=1}}) void {
        var sum: u32 = 0;
        for (0..grid_offsets.ptr.len) |i| {
            grid_offsets_prefix.ptr[i] = sum;
            sum += grid_offsets.ptr[i];
        }
    }
};

comptime {
    @export(&Vertex.particle_quad,   .{ .name = "vert" });
    @export(&Vertex.triangle,   .{ .name = "vert_hdr" });
    @export(&Fragment.particle_quad, .{ .name = "frag" });
    @export(&Fragment.triangle, .{ .name = "frag_hdr" });
    @export(&Compute.main,  .{ .name = "compute" });
    @export(&Compute.compute_grid_offsets, .{ .name = "compute_grid_offsets"});
    @export(&Compute.compute_offset_prefix, .{ .name = "compute_offset_prefix"});
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

const std = @import("std");
const spirv = std.spirv;
const driver = @import("main.zig");
const vulkan = @import("vulkan.zig");

const Particle = driver.Particle;
const Force_Config = driver.Force_Config;

fn SpirvArray(comptime T: type) type {
    return extern struct {
        ptr: @SpirvType(.{ .runtime_array = T }),
    };
}
pub const Image = @SpirvType(.{ .image = .{
        .usage = .{ .sampled = f32 },
        .format = .rgba16f,
        .dim = .@"2d",
        .depth = .not_depth,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } });
pub const SampledImage = @SpirvType(.{ .sampled_image = Image });


const Particle_Array = SpirvArray(driver.Particle);
const U32_Array      = SpirvArray(u32);

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

pub fn splat3(a: f32) V3 {
    return @splat(a);
}
