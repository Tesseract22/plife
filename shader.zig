pub const PARTICLE_SIZE = 0.03;
pub const PARTICLE_KERNEL_SIZE = 0.005;
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

        center.* = camera.translate(particle.pos);
        const pos_offset = center.* + (positions[off_i] * m.splat2(PARTICLE_SIZE)) * m.splat2(camera.zoom);
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

        const constant = @extern(*addrspace(.push_constant) vulkan.Triangle_Constant, .{.name = "push_constant"});

        frag_color.* = color;

        tex_coord.* = in_tex_coord;
        var cam = constant.camera;
        cam.pos[1] = -cam.pos[1];
        const pos_offset = cam.translate(pos);
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
        const d = m.len(frag_pos.*-center.*);

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
        return hdrColor / (hdrColor + m.splat3(1.0));
    }

    // adapted from https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
    fn aces_tm(x: V3) V3 {
        const a = m.splat3(2.51);
        const b = m.splat3(0.03);
        const c = m.splat3(2.43);
        const d = m.splat3(0.59);
        const e = m.splat3(0.14);
        return std.math.clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
    }

    fn exposure_tm(hdrColor: V3) V3 {
        const exposure = m.splat3(0.5);
        return m.splat3(1.0) - @exp(-hdrColor * exposure);
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

        if (constant.pure_color == 1) {
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
        const d = m.len(l); // since we uses linear_force, zero distance does not cause infinite force
        const unit_l = if (d == 0) .{1,0} else l / m.splat2(d);
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
            m.splat2(interact_force_ab) * unit_l
            + m.splat2(collision_force) * unit_l;

    }

    pub fn compute_interaction_with_bin(particle_i: u32, bin: u32) V2 {
        const start = grid_offsets_prefix.ptr[bin];
        const end   = grid_offsets_prefix.ptr[bin+1];
        return compute_interaction_with_range(particle_i, start, end);
    }

    pub fn compute_interaction_with_range(particle_i: u32, start: u32, end: u32) V2 {
        var spd = m.splat2(0);
        for (start..end) |j| {
            const particle_j = particles_sorted.ptr[j];
            if (particle_i == particle_j) continue;
            const a = particles_in.ptr[particle_i];
            const b = particles_in.ptr[particle_j];
            spd += compute_interaction(a, b);
        }
        return spd;
    }

    // TODO: make this configurable from CPU
    const PARTICLE_DRAG = 40;
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
    const grid_offsets_prefix_copy = @extern(*addrspace(.storage_buffer) U32_Array , .{
        .name = "grid_offsets_prefix_copy",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 4 } },
    });
    const particles_sorted = @extern(*addrspace(.storage_buffer) U32_Array , .{
        .name = "particles_sorted",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 5 } },
    });

    pub fn main() callconv(.{ .spirv_kernel = .{.x=driver.KERNEL_WORKGROUP_X,.y=1,.z=1}}) void {
        const dt = 1.0/120.0;
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;

        var spd = particles_in.ptr[i].spd;
        var pos = particles_in.ptr[i].pos;

        // spd = spd + compute_interaction_with_range(i, 0, particles_in.ptr.len) * m.splat2(dt);
                const cell = m.cell_from_pos(pos).?;
                const cell_i: @Vector(2, f32) = .{@floatFromInt(cell[0]), @floatFromInt(cell[1])};
                inline for (0..3) |x| {
                    inline for (0..3) |y| {
                        const neighbor_i = @Vector(2, f32) {cell_i[0]+x-1, cell_i[1]+y-1};
                        if (neighbor_i[0] >= driver.GRID_CELL_SIDE_COUNT or neighbor_i[0] < 0) {} 
                        else if (neighbor_i[1] >= driver.GRID_CELL_SIDE_COUNT or neighbor_i[1] < 0) {}
                        else {
                            const bin = m.bin_from_cell(.{ @intFromFloat(neighbor_i[0]), @intFromFloat(neighbor_i[1]) });
                            spd = spd + compute_interaction_with_bin(i, bin) * m.splat2(dt);
                        }
                    }
                }
                // for (0..grid_offsets.ptr.len) |bin| {
                //     spd = spd + compute_interaction_with_bin(i, bin) * m.splat2(dt);
                // }

        // const bin = m.bin_from_cell(cell);
        pos = pos + m.splat2(dt) * spd;
        spd = spd * m.splat2(@exp(-PARTICLE_DRAG*dt*m.len(spd)));
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
                pos = @mod(pos + m.splat2(1), m.splat2(2)) - m.splat2(1);
            },
        }
        particles_out.ptr[i].spd = spd;
        particles_out.ptr[i].pos = pos;
    }

    pub fn compute_grid_offsets() callconv(.{ .spirv_kernel = .{.x=driver.KERNEL_WORKGROUP_X,.y=1,.z=1}}) void {
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;
        const particle = particles_in.ptr[i];
        const cell = m.cell_from_pos(particle.pos).?;
        const bin = m.bin_from_cell(cell);

        // note: not yet supported in zig compiler
        // _ = @atomicRmw(u32, &grid_offsets.ptr[bin], .Add, 1, .monotonic);
        const sem = spirv.MemorySemantics {};
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
            grid_offsets_prefix_copy.ptr[i] = sum;
            sum += grid_offsets.ptr[i];
        }
        grid_offsets_prefix.ptr[grid_offsets_prefix.ptr.len-1] = sum;
        grid_offsets_prefix_copy.ptr[grid_offsets_prefix.ptr.len-1] = sum;
    }

    pub fn sort_particles() callconv(.{ .spirv_kernel = .{.x=driver.KERNEL_WORKGROUP_X,.y=1,.z=1}}) void {
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;
        const particle = particles_in.ptr[i];
        const cell = m.cell_from_pos(particle.pos).?;
        const bin = m.bin_from_cell(cell);

        const sem = spirv.MemorySemantics {};
        const offset = asm volatile (
            \\%ret = OpAtomicIAdd %t %ptr %scope %sem %val
            : [ret] "" (-> u32)
            : [t] "t" (u32),
            [ptr] "" (&grid_offsets_prefix_copy.ptr[bin]),
            [scope] "" (@as(u32, @intFromEnum(spirv.Scope.device))),
            [sem] "" (@as(u32, @bitCast(sem))),
            [val] "i" (1),
        );
        particles_sorted.ptr[offset] = i;
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
    @export(&Compute.sort_particles, .{ .name = "sort_particles"});
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

const std = @import("std");
const spirv = std.spirv;
const driver = @import("main.zig");
const m = @import("math.zig");
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
        .format = .unknown,
        .dim = .@"2d",
        .depth = .not_depth,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } });
pub const SampledImage = @SpirvType(.{ .sampled_image = Image });


const Particle_Array = SpirvArray(driver.Particle);
const U32_Array      = SpirvArray(u32);
