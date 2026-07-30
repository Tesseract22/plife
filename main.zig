pub const KERNEL_WORKGROUP_X = 128;
pub const MAX_PARTICLE_SPECIE = 4;

pub const GRID_CELL_SIDE_COUNT = 10;
pub const GRID_CELL_COUNT      = GRID_CELL_SIDE_COUNT * GRID_CELL_SIDE_COUNT;
pub const GRID_CELL_SIZE       = 1.0/@as(comptime_float, GRID_CELL_SIDE_COUNT);

pub const Particle = extern struct {
    pos: [2]f32,
    spd: [2]f32,
    specie: u32,

    pub fn get_input_attrs(binding: u32) [2]v.VertexInputAttributeDescription {
        return .{
            .{
                .location = 0,
                .binding = binding,
                .format = .r32g32_sfloat,
                .offset = @offsetOf(Particle, "pos"),
            },
            .{
                .location = 1,
                .binding = binding,
                .format = .r8_uint,
                .offset = @offsetOf(Particle, "pos"),

            }
        };
    }
};

pub const Particle_Specie = extern struct {
    color: [3]f32,
};

pub const Force_Config = extern struct {
    radius: f32,
    strength: f32, // >0 -> repel, <0 -> attract
};

fn float_range(random: std.Random, min: f32, max: f32) f32 {
    return random.float(f32) * (max - min) + min;
}

pub fn randomize_particle_specie(species: []Particle_Specie, random: std.Random) void {
    for (species) |*sp| {
        const hsv = [3]f32 { random.float(f32) * 360, float_range(random, 0.5, 1), float_range(random, 0.5, 1) };
        sp.color = m.rgb_from_hsv(hsv);
    }
}

pub fn generate_particle(particles: []Particle, specie_count: usize, rand: std.Random) void {
    assert(specie_count <= MAX_PARTICLE_SPECIE);
    for (particles) |*p| {
        p.pos = .{ float_range(rand, -1, 1), float_range(rand, -1, 1) };
        p.spd = .{ float_range(rand, -1, 1), float_range(rand, -1, 1) };
        p.specie = rand.int(u8) % @as(u8, @intCast(specie_count));
    }
}

const particle_drag = 20;
var r_force_radius_max: f32 = 0.099;
var r_force_radius_min: f32 = 0.05;
var r_force_strength_max: f32 = 0.20;
var r_force_strength_min: f32 = 0.05;

fn random_sign(random: std.Random) f32 {
    return if (random.boolean()) 1 else -1;
}

pub fn randomize_config(particle_force_configs: []Force_Config, specie_ct: u32, rand: std.Random) void {
    assert(particle_force_configs.len == specie_ct * specie_ct);
    // particle_kind = random.int(u8) % 5 + 2;
    var i: usize = 0;
    for (0..specie_ct) |_| {
        for (0..specie_ct) |_| {
            particle_force_configs[i] = 
                .{
                    .radius = float_range(rand, r_force_radius_min, r_force_radius_max),
                    .strength = random_sign(rand) * float_range(rand, r_force_strength_min, r_force_strength_max),
                };
            i += 1;
        }
    }
}

pub const Camera = extern struct {
    pos: [2]f32 = .{0,0},
    zoom: f32 = 1,
};

pub const Push_Constant = extern struct {
    camera: Camera,

    ping_pong: bool,
    species: [MAX_PARTICLE_SPECIE]Particle_Specie,
    specie_ct: u32,
    particle_ct: u32,
    collision_cfg: Force_Config,
    particle_force_configs: [MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE]Force_Config,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io    = init.io;
    var rand_backend = std.Random.Xoroshiro128.init(@intCast(std.Io.Timestamp.now(io, .boot).nanoseconds));
    const rand = rand_backend.random();

    var   particles  : [40000]Particle = undefined;
    var   species    : [MAX_PARTICLE_SPECIE]Particle_Specie = undefined;
    const specie_ct  : u32 = 3;
    var   particle_force_configs : [MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE]Force_Config = undefined;
    const collision_cfg = Force_Config {
        .radius = 0.025,
        .strength = 0.6,
    };


    const particles_size = @sizeOf(Particle) * particles.len;
    randomize_particle_specie(&species, rand);
    randomize_config(particle_force_configs[0..specie_ct*specie_ct], specie_ct, rand);
    generate_particle(&particles, specie_ct, rand);


    const WINDOW_W = 1000;
    const WINDOW_H = 1000;
    const APP_NAME = "Vulkan 1.0 Example";
    _ = r.RGFW_init(APP_NAME, 0);
    const window = r.RGFW_createWindow(APP_NAME, 0, 0,
        WINDOW_W, WINDOW_H, r.RGFW_windowCenter)
        orelse @panic("cannot create window");

    //
    // Create Instance
    //
    _ = try vulkan.init_instance();
    _ = try vulkan.init_surface(window);
    defer vulkan.cleanup();
    const device = try vulkan.init_device(arena, WINDOW_W, WINDOW_H);
    vulkan.init_queues(device);
    _ = try vulkan.init_swapchain(device);
    _ = try vulkan.init_image_views(arena, device);
    try vulkan.init_shader_modules();
    try vulkan.init_render_pass();
    try vulkan.init_hdr_render_pass();

    _ = try vulkan.init_command_pool(device);
    const part_buf1 = try vulkan.create_storage_buffer(particles_size, true);
    defer part_buf1.destroy();
    const part_buf2 = try vulkan.create_storage_buffer(particles_size, true);
    defer part_buf2.destroy();
    const grid_offsets_buf = try vulkan.create_storage_buffer(GRID_CELL_COUNT * @sizeOf(u32), false); // no need to initialzied
    defer grid_offsets_buf.destroy();

    const staging_buf = try vulkan.create_staging_buffer(particles_size);
    defer staging_buf.destroy();

    const staging_mapped = try vulkan.map_mem(staging_buf.mem, Particle, particles.len);
    @memcpy(staging_mapped, &particles);
    device.unmapMemory(staging_buf.mem);

    try vulkan.copy_buffer(part_buf1, staging_buf, particles_size);
    try vulkan.copy_buffer(part_buf2, staging_buf, particles_size);

    try vulkan.init_descriptor_set(.{part_buf1.buf, part_buf2.buf}, grid_offsets_buf.buf);
    try vulkan.init_pipeline_layout(@sizeOf(Push_Constant));
    try vulkan.init_pipeline(@sizeOf(Particle), &Particle.get_input_attrs(0));
    try vulkan.init_hdr_pipeline();
    try vulkan.init_compute_pipeline();
    _ = try vulkan.init_frame_buffers(arena, device);

    try vulkan.init_command_buffers(device);
    try vulkan.init_sync_primitives(device);

    const target_fps = 60.0;
    const target_dt  = 1.0/target_fps;
    var   dt: f32    = target_dt;

    var camera = Camera {};
    var camera_target = Camera {};
    
    var ping_pong = true;
    while (r.RGFW_window_shouldClose(window) == 0) {
        // TODO: limit frame rate
        const start = std.Io.Timestamp.now(io, .boot);
        defer {
            const end = std.Io.Timestamp.now(io, .boot);
            dt = @as(f32, @floatFromInt(start.durationTo(end).nanoseconds)) / std.time.ns_per_s;
            if (dt < target_dt) {
                io.sleep(.{ .nanoseconds = @intFromFloat((target_dt - dt) * std.time.ns_per_s) }, .boot)
                    catch unreachable;
                dt = target_dt;
            }

        }
        if (vulkan.state.frame_counter % 20 == 0) {
            std.log.info("dt={}, fps={}", .{dt, 1.0/dt});
        }

        // FIXME: when window resized, we need to recreate swap chain
        r.RGFW_pollEvents();

        if (r.RGFW_isKeyDown(r.RGFW_keyA) == 1) {
            camera_target.pos[0] += CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyD) == 1) {
            camera_target.pos[0] -= CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyW) == 1) {
            camera_target.pos[1] += CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyS) == 1) {
            camera_target.pos[1] -= CAMERA_MOV_SPD * dt;
        }

        if (r.RGFW_isKeyPressed(r.RGFW_keyR) == 1) {
            randomize_particle_specie(&species, rand);
            randomize_config(particle_force_configs[0..specie_ct*specie_ct], specie_ct, rand);
            generate_particle(&particles, specie_ct, rand);
            @memcpy(staging_mapped, &particles);
            try vulkan.copy_buffer(part_buf1, staging_buf, particles_size);
            try vulkan.copy_buffer(part_buf2, staging_buf, particles_size);
        }

        const scroll = get_mouse_scroll();
        const wheel = scroll[1];
        camera_target.zoom = std.math.clamp(@exp2(@log2(camera_target.zoom)+wheel*CAMERA_ZOOM_SPD), 0.5, 64.0);

        camera.zoom = exp_smooth(camera.zoom, camera_target.zoom, dt * CAMERA_SMOOTH_SPD);
        camera.pos[0] = exp_smooth(camera.pos[0], camera_target.pos[0], dt * CAMERA_SMOOTH_SPD);
        camera.pos[1] = exp_smooth(camera.pos[1], camera_target.pos[1], dt * CAMERA_SMOOTH_SPD);

        vulkan.set_push_constant(Push_Constant, &.{
            .camera = camera, .species = species, .specie_ct = specie_ct, .particle_ct = particles.len,
            .collision_cfg = collision_cfg, .particle_force_configs = particle_force_configs, .ping_pong = ping_pong });
        try vulkan.dispatch_compute((particles.len+KERNEL_WORKGROUP_X-1)/KERNEL_WORKGROUP_X, 0);
        // try vulkan.dispatch_compute((particles.len+KERNEL_WORKGROUP_X-1)/KERNEL_WORKGROUP_X, 1);
        try vulkan.draw_frame(@intCast(particles.len * VERT_PER_PARTICLE), part_buf1.buf);
        ping_pong = !ping_pong;
    }
    try device.deviceWaitIdle();

    r.RGFW_window_close(window);
    r.RGFW_deinit();
}

const vulkan = @import("vulkan.zig");
const v = @import("vk.zig");
const r = @import("RGFW");
const m = @import("math.zig");

const Instance = v.InstanceProxy;
const Device = v.DeviceProxy;

const std = @import("std");
const log = std.log;
const fatal = std.process.fatal;
const assert = std.debug.assert;

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

pub const VERT_PER_PARTICLE = 6;

pub fn get_mouse_scroll() [2]f32 {
    var x: f32 = undefined;
    var y: f32 = undefined;

    r.RGFW_getMouseScroll(&x, &y);

    return .{x,y};
}

const CAMERA_MOV_SPD  = 0.7;
const CAMERA_ZOOM_SPD = 0.3;
const CAMERA_SMOOTH_SPD = 10;

pub fn exp_smooth(current: f32, target: f32, delta: f32) f32 {
    return current + (target - current) * (1 - @exp(-delta));
}

const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});
