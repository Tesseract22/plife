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

    const constant = @extern(*addrspace(.push_constant) driver.Push_Constant, .{.name = "push_constant"});
    const particles1 = @extern(*addrspace(.storage_buffer) const ParticleArray , .{
        .name = "particles1",
        .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
    });
    const particles2 = @extern(*addrspace(.storage_buffer) const ParticleArray , .{
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

    fn main() callconv(.spirv_vertex) void {

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

pub const Compute = struct {
    const constant = @extern(*addrspace(.push_constant) driver.Push_Constant, .{.name = "push_constant"});

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
        //const interact_cfg_ba = particle_force_configs.items[b.kind * particle_kind + a.kind];
        const interact_force_ab = linear_force(interact_cfg_ab, d);
        //const interact_force_ba = linear_force(interact_cfg_ba, d);
        
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

    const particle_drag = 20;

    pub fn main() callconv(.{ .spirv_kernel = .{.x=1,.y=1,.z=1}}) void {
        const dt = 1.0/60.0;
        const particles_in = @extern(*addrspace(.storage_buffer) ParticleArray , .{
            .name = "particles1",
            .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
        });
        const particles_out = @extern(*addrspace(.storage_buffer) ParticleArray , .{
            .name = "particles2",
            .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
        });
        const i = spirv.global_invocation_id[0];
        if (i >= particles_in.ptr.len) return;

        var spd = particles_in.ptr[i].spd;
        var pos = particles_in.ptr[i].pos;
        for (0..particles_in.ptr.len) |j| {
            if (i == j) continue;
            spd = spd + compute_interaction(particles_in.ptr[i], particles_in.ptr[j]) * splat2(dt);
        }
        pos = pos + splat2(dt) * spd;
        spd = spd * splat2(@exp(-particle_drag*dt*len(spd)));
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
        particles_out.ptr[i].spd = spd;
        particles_out.ptr[i].pos = pos;
    }

};

comptime {
    @export(&Vertex.main,   .{ .name = "vert" });
    @export(&Fragment.main, .{ .name = "frag" });
    @export(&Compute.main, .{ .name = "compute" });
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

const std = @import("std");
const spirv = std.spirv;
const driver = @import("main.zig");

const Particle = driver.Particle;
const Force_Config = driver.Force_Config;

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
