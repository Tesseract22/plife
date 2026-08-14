pub const KERNEL_WORKGROUP_X = 64;
pub const MAX_PARTICLE_SPECIE = 20;

pub const GRID_CELL_SIDE_COUNT = 30;
pub const GRID_CELL_COUNT      = GRID_CELL_SIDE_COUNT * GRID_CELL_SIDE_COUNT;
pub const GRID_CELL_SIZE       = 2.0/@as(comptime_float, GRID_CELL_SIDE_COUNT);

pub const Particle = extern struct {
    pos: [2]f32 align(16),
    spd: [2]f32,
    specie: u32,
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

// Too much randomness is boring!
// When there are many species, each randomization of color become very similar and boring,
// because they fill the color space somewhat evenly.
//
// To remedy this, we first randomly choose a smaller number of color ranges,
// and then randomize based on those.
var pre_random_specie: [MAX_PARTICLE_SPECIE][3]f32 = undefined;
var pre_random_ct: u32 = 0;
pub fn randomize_particle_specie(species: []Particle_Specie, random: std.Random) void {
    pre_random_ct = @intFromFloat(@sqrt(@as(f32, @floatFromInt(species.len))));
    pre_random_ct += 2;
    for (0..pre_random_ct) |i| {
        pre_random_specie[i] = [3]f32 { random.float(f32) * 360, float_range(random, 0.7, 1), float_range(random, 0.2, 1) };
    }
    for (species) |*sp| {
        var hsv = pre_random_specie[random.int(u32) % pre_random_ct];
        hsv[0] += float_range(random, -20, 20);
        hsv[0] = @mod(hsv[0], 360);
        sp.color = m.rgb_from_hsv(hsv);
    }
}

pub fn generate_particle(particles: []Particle, specie_count: usize, rand: std.Random) void {
    assert(specie_count <= MAX_PARTICLE_SPECIE);
    for (particles) |*p| {
        p.pos = .{ float_range(rand, -1, 1), float_range(rand, -1, 1) };
        p.spd = .{ 0, 0 };
        p.specie = rand.int(u8) % @as(u8, @intCast(specie_count));
    }
}

const Bound = struct {
    min: f32, max: f32,

    pub const Order = enum {
        lt, gt, none,
    };

    pub fn init(left: f32, right: f32) Bound {
        assert(left < right);
        return .{ .min = left, .max = right };
    }

    pub fn comp(bound: Bound, f: f32) Order {
        if (bound.max < f) return .lt;
        if (bound.min > f) return .gt;
        return .none;
    }

    pub fn comp_bound(bound: Bound, other: Bound) Order {
        if (bound.max < other.min) return .lt;
        if (bound.min > other.max) return .gt;
        return .none;
    }

    pub fn random(bound: Bound, rand: std.Random) f32 {
        return float_range(rand, bound.min, bound.max);
    }
};

const r_force_radius       = Bound.init(0.03, 0.05);
var   b_force_radius       = r_force_radius;
const r_force_strength     = Bound.init(0.02, 0.3);
var   b_force_strength     = r_force_strength;

const b_collision_radius   = Bound.init(0.001, 0.029);
const b_collision_strength = Bound.init(0.31, 0.8);
const b_central_strength   = Bound.init(-1, 1);

const b_drag               = Bound.init(0, 100);

const b_simulation_dt      = Bound.init(0, 1.0/60.0);

comptime {
    if (r_force_radius.comp(GRID_CELL_SIZE) != .lt) {
        std.debug.panic("maximum force radius is {}, but grid cell size is {}", .{ r_force_radius.max, GRID_CELL_SIZE});
    }
    assert(r_force_radius.comp_bound(b_collision_radius) == .gt);
    assert(r_force_strength.comp_bound(b_collision_strength) == .lt);
}

fn random_sign(random: std.Random) f32 {
    return if (random.boolean()) 1 else -1;
}

pub fn randomize_config(particle_force_configs: []Force_Config, specie_ct: u32, always_self_attract: bool, rand: std.Random) void {
    assert(particle_force_configs.len >= specie_ct * specie_ct);
    // particle_kind = random.int(u8) % 5 + 2;
    var count: usize = 0;
    for (0..specie_ct) |i| {
        for (0..specie_ct) |j| {
            const sign = if (always_self_attract and i == j) -1 else random_sign(rand);
            particle_force_configs[count] =
                .{
                    .radius = b_force_radius.random(rand),
                    .strength = sign * b_force_strength.random(rand),
                };
            count += 1;
        }
    }
}

pub const Method = enum(u32) { none, brute, grid };

pub const Particle_Constant = extern struct {
    camera: Camera,

    drag: f32,
    ping_pong: bool,
    specie_ct: u32,
    particle_ct: u32,
    collision_cfg: Force_Config,
    aspect_ratio: f32,
    dt: f32,

    mouse_pos: [2]f32,
    mouse_action: enum(u32) { none, push, pull, },

    central_force: f32,
};

pub const Annoucement = struct {
    const default_color = m.color_mul(UI.theme.text_color, UI.theme.btn_hover_color_mul);
    t: f32,
    color: [4]f32 = default_color,
    text: []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn update(self: *Annoucement, dt: f32) void {
        if (self.t <= 0) {
            self.color[3] = exp_smooth(self.color[3], 0, dt);
        }
        self.t -= dt;
    }

    pub fn reset(self: *Annoucement, t: f32, comptime fmt: []const u8, args: anytype) void {
        _ = self.arena.reset(.retain_capacity); 
        self.t = t;
        self.text = std.fmt.allocPrint(self.arena.allocator(), fmt, args) catch @panic("OOM");
        self.color = default_color;
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io    = init.io;
    var rand_backend = std.Random.Xoroshiro128.init(@intCast(std.Io.Timestamp.now(io, .boot).nanoseconds));
    const rand = rand_backend.random();

    var   particles  : [80000]Particle = undefined;
    var   particle_ct: u32 = particles.len/2;
    var   always_self_attract = true;
    var   config = Configuration {
        .specie_ct = 4,
        .particle_force_configs = undefined,
        .collision_force_config = undefined, // duplicated
        .species                = undefined,
    };

    const particles_size = @sizeOf(Particle) * particles.len;
    const configs_size = MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE * @sizeOf(Force_Config);
    const species_size = MAX_PARTICLE_SPECIE * @sizeOf(Particle_Specie);
    randomize_particle_specie(config.species[0..config.specie_ct], rand);
    randomize_config(config.particle_force_configs[0..config.specie_ct*config.specie_ct], config.specie_ct, always_self_attract, rand);
    generate_particle(&particles, config.specie_ct, rand);


    // TODO: handle window resize
    const WINDOW_W = 1900;
    const WINDOW_H = 1000;
    // const ASPECT_RATION = WINDOW_W/WINDOW_H;
    const APP_NAME = "Particle Life";
    _ = r.RGFW_init(APP_NAME, 0);
    const window = r.RGFW_createWindow(APP_NAME, 0, 0,
        WINDOW_W, WINDOW_H, r.RGFW_windowCenter | r.RGFW_windowAllowDND)
        orelse @panic("cannot create window");
    r.RGFW_setBuildDND(1);

    //
    // Create Instance
    //
    try vulkan.init_instance(arena);
    try vulkan.init_surface(window);
    // defer vulkan.cleanup();
    const device = try vulkan.init_device(WINDOW_W, WINDOW_H);
    vulkan.init_queues(device);
    try vulkan.init_swapchain(device);
    try vulkan.init_image_views(device);
    try vulkan.init_shader_modules();
    try vulkan.init_render_pass();
    try vulkan.init_hdr_render_pass();

    _ = try vulkan.init_command_pool(device);
    try vulkan.init_font();
    const part_buf1 = try vulkan.create_storage_buffer(particles_size, true);
    defer part_buf1.destroy();
    const part_buf2 = try vulkan.create_storage_buffer(particles_size, true);
    defer part_buf2.destroy();
    const force_configs_buf = try vulkan.create_storage_buffer(configs_size, false);
    defer force_configs_buf.destroy();
    const species_buf = try vulkan.create_storage_buffer(species_size, false);
    defer species_buf.destroy();
    const grid_offsets_buf = try vulkan.create_buffer(
        GRID_CELL_COUNT * @sizeOf(u32), .{ .storage_buffer = true, .transfer_src = true, .transfer_dst = true }, .{ .device_local = true });
    defer grid_offsets_buf.destroy();

    const grid_offsets_prefix_buf = try vulkan.create_buffer(
        (GRID_CELL_COUNT+1) * @sizeOf(u32), .{ .storage_buffer = true, .transfer_src = true, .transfer_dst = true }, .{ .device_local = true });
    defer grid_offsets_prefix_buf.destroy();

    const grid_offsets_prefix_copy_buf = try vulkan.create_buffer(
        (GRID_CELL_COUNT+1) * @sizeOf(u32), .{ .storage_buffer = true, .transfer_src = true, .transfer_dst = true }, .{ .device_local = true });
    defer grid_offsets_prefix_copy_buf.destroy();

    const part_sorted_buf = try vulkan.create_storage_buffer(particles_size, true);
    defer part_sorted_buf.destroy();

    const staging_size = @max(@max(particles_size, configs_size), species_size);
    const staging_buf = try vulkan.create_staging_buffer(staging_size);
    defer staging_buf.destroy();

    const staging_mapped = try vulkan.map_mem(staging_buf.mem, u8, staging_size);
    defer device.unmapMemory(staging_buf.mem);
    {
        const size = vulkan.copy_to_bytes(staging_mapped, particles[0..particle_ct]);
        try vulkan.copy_buffer(part_buf1, staging_buf, size);
        try vulkan.copy_buffer(part_buf2, staging_buf, size);
    }
    try vulkan.upload_with_staging(force_configs_buf, staging_buf, staging_mapped, config.particle_force_configs[0..config.specie_ct*config.specie_ct]);
    try vulkan.upload_with_staging(species_buf, staging_buf, staging_mapped, config.species[0..config.specie_ct]);

    try vulkan.init_particle_desc_set(
        .{part_buf1.buf, part_buf2.buf},
        grid_offsets_buf.buf, grid_offsets_prefix_buf.buf, grid_offsets_prefix_copy_buf.buf,
        part_sorted_buf.buf, force_configs_buf.buf, species_buf.buf);
    try vulkan.init_triangle_desc_set();
    try vulkan.init_pipeline_layout(@sizeOf(Particle_Constant));
    try vulkan.init_pipeline();
    try vulkan.init_off_screen_pipeline();
    try vulkan.init_compute_pipeline();
    _ = try vulkan.init_frame_buffers(arena, device);

    try vulkan.init_command_buffers(device);
    try vulkan.init_sync_primitives(device);
    vulkan.write_texture_to_descriptor(0, vulkan.state.hdr_texture.view);
    vulkan.write_texture_to_descriptor(1, vulkan.state.hdr_texture.view);

    const target_fps = 60.0;
    const target_dt  = 1.0/target_fps;
    var   dt     : f32 = target_dt;
    var   real_dt: f32 = target_dt;

    var camera_target = Camera {};

    UI.init(init.gpa);
    defer UI.deinit();

    var display_gui = true;
    var particle_constant = Particle_Constant {
        .camera = .{}, .specie_ct = config.specie_ct, .particle_ct = particle_ct,
        .collision_cfg = .{.radius = 0.02,.strength = 0.5}, .drag = 20, .ping_pong = true,
        .aspect_ratio = vulkan.state.aspect_ratio, .dt = 1.0/120.0,
        .mouse_pos = .{0,0}, .mouse_action = .none, .central_force = 0,
    };
    var annoucement = Annoucement {
        .arena = .init(init.gpa),
        .t = 0,
        .text = "",
    };
    defer annoucement.arena.deinit();
    var config_fresh = false; // keep track of if the config is newly loaded from a file
    var lock_fps = true;
    var prev_mouse = V2 {0,0};
    while (r.RGFW_window_shouldClose(window) == 0) {
        _ = UI.frame.arena.reset(.retain_capacity);
        UI.frame.mouse_on_ui = false;
        // TODO: limit frame rate
        const start = std.Io.Timestamp.now(io, .boot);
        defer {
            const end = std.Io.Timestamp.now(io, .boot);
            dt = @as(f32, @floatFromInt(start.durationTo(end).nanoseconds)) / std.time.ns_per_s;
            real_dt = dt;
            if (lock_fps and dt < target_dt) {
                io.sleep(.{ .nanoseconds = @intFromFloat((target_dt - dt) * std.time.ns_per_s) }, .boot)
                    catch unreachable;
                dt = target_dt;
            }
        }
        if (!lock_fps) {
            particle_constant.dt = dt/2.0;
        }

        // FIXME: when window resized, we need to recreate swap chain
        r.RGFW_pollEvents();

        if (r.RGFW_isKeyDown(r.RGFW_keyA) == 1) {
            camera_target.pos[0] -= CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyD) == 1) {
            camera_target.pos[0] += CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyW) == 1) {
            camera_target.pos[1] -= CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyDown(r.RGFW_keyS) == 1) {
            camera_target.pos[1] += CAMERA_MOV_SPD * dt;
        }
        if (r.RGFW_isKeyPressed(r.RGFW_keyG) == 1) {
            display_gui = !display_gui;
        }
        if (r.RGFW_isKeyPressed(r.RGFW_keyE) == 1) {
            config.collision_force_config = particle_constant.collision_cfg;
            var allocating = std.Io.Writer.Allocating.init(UI.frame.arena.allocator());
            try config.print(&allocating.writer);
            const transfer = r.RGFW_dataTransfer {
                .data = allocating.written().ptr,
                .length = allocating.written().len,
                .type = r.RGFW_dataText,
            };
            if (r.RGFW_writeClipboard(&transfer) == 1) {
                annoucement.reset(5, "Configuration saved to clipboard", .{});
            } else {
                annoucement.reset(5, "Cannot saved configuration", .{});
            }
        }
        if (r.RGFW_window_getDataDrop(window)) |data_drop_ptr| {
            const data_drop = data_drop_ptr[0];
            log.info("data_drop: len={}, type={}", .{data_drop.length, data_drop.type});
            const path = data_drop.data[0..data_drop.length-1]; // that last byte seems to be garbage for whatever reason
            log.info("path: {s}", .{path});
            const basename = std.fs.path.basename(path);
            if (Configuration.deserialize(init.io, path)) |new_config| {
                config = new_config;
                config_fresh = true;
                annoucement.reset(5, "New Configuration {s} Loaded!", .{basename});
            } else |e| {
                annoucement.reset(5, "cannot load config file: {}", .{e});
            }
        }

        if (r.RGFW_isKeyPressed(r.RGFW_keyR) == 1) {
            if (r.RGFW_isKeyDown(r.RGFW_keyShiftL) == 1) {
                particle_constant.specie_ct = config.specie_ct;
                randomize_particle_specie(config.species[0..particle_constant.specie_ct], rand);
                randomize_config(&config.particle_force_configs, particle_constant.specie_ct, always_self_attract, rand);
                config_fresh = true;
            }
            if (config_fresh) {
                try vulkan.upload_with_staging(force_configs_buf, staging_buf, staging_mapped, config.particle_force_configs[0..config.specie_ct*config.specie_ct]);
                try vulkan.upload_with_staging(species_buf, staging_buf, staging_mapped, config.species[0..config.specie_ct]);
                config_fresh = false;
            }
            particle_constant.particle_ct = particle_ct;
            generate_particle(&particles, particle_constant.specie_ct, rand);
            {
                const size = vulkan.copy_to_bytes(staging_mapped, particles[0..particle_ct]);
                try vulkan.copy_buffer(part_buf1, staging_buf, size);
                try vulkan.copy_buffer(part_buf2, staging_buf, size);
            }
        }

        const scroll = get_mouse_scroll();
        const wheel = scroll[1];
        camera_target.zoom = std.math.clamp(@exp2(@log2(camera_target.zoom)+wheel*CAMERA_ZOOM_SPD), 0.5, 64.0);

        particle_constant.camera.zoom = exp_smooth(particle_constant.camera.zoom, camera_target.zoom, dt * CAMERA_SMOOTH_SPD);
        particle_constant.camera.pos[0] = exp_smooth(particle_constant.camera.pos[0], camera_target.pos[0], dt * CAMERA_SMOOTH_SPD);
        particle_constant.camera.pos[1] = exp_smooth(particle_constant.camera.pos[1], camera_target.pos[1], dt * CAMERA_SMOOTH_SPD);

        const mouse_screen = get_mouse(window);
        UI.frame.mouse = ((mouse_screen / V2 {WINDOW_W, WINDOW_H})*m.splat2(2) - m.splat2(1)) * V2{vulkan.state.aspect_ratio, 1};
        defer prev_mouse = UI.frame.mouse;
        UI.frame.mouse_delta = UI.frame.mouse-prev_mouse;

        particle_constant.mouse_action = .none;
        particle_constant.mouse_pos =
                UI.frame.mouse / m.splat2(particle_constant.camera.zoom)
                + m.apply_aspect_ratio(particle_constant.camera.pos, 1/vulkan.state.aspect_ratio);

        if (!UI.frame.mouse_on_ui and is_mouse_down()) particle_constant.mouse_action = .push
        else if (!UI.frame.mouse_on_ui and is_mouse_right_down()) particle_constant.mouse_action = .pull;

        const compute_durations = blk: {
            try vulkan.compute_fence();
            const compute_durations = try vulkan.begin_dispatch();

            vulkan.push_constant(Particle_Constant, &particle_constant);

            vulkan.clear_buf(grid_offsets_buf);
            vulkan.clear_buf(grid_offsets_prefix_buf);
            vulkan.clear_buf(grid_offsets_prefix_copy_buf);
            vulkan.use_compute(0);
            vulkan.dispatch_compute((particles.len+KERNEL_WORKGROUP_X-1)/KERNEL_WORKGROUP_X);
            vulkan.sync_buf(grid_offsets_buf);

            vulkan.use_compute(1);
            vulkan.dispatch_compute(1);
            vulkan.sync_buf(grid_offsets_prefix_buf);
            vulkan.sync_buf(grid_offsets_prefix_copy_buf);

            vulkan.use_compute(2);
            vulkan.dispatch_compute((particles.len+KERNEL_WORKGROUP_X-1)/KERNEL_WORKGROUP_X);
            vulkan.sync_buf(part_sorted_buf);

            if (particle_constant.dt != 0) {
                vulkan.use_compute(3);
                vulkan.dispatch_compute((particles.len+KERNEL_WORKGROUP_X-1)/KERNEL_WORKGROUP_X);
            }

            try vulkan.end_dispatch();
            break :blk compute_durations;
        };
        try vulkan.begin_draw();

        vulkan.push_constant(Particle_Constant, &particle_constant);
        vulkan.draw_particles_to_off_screen(@intCast(particle_constant.particle_ct * VERT_PER_PARTICLE));

        vulkan.begin_2d();
        draw.texture(.screen(), .{1,1,1,1}, vulkan.state.hdr_texture.view);
        if (display_gui) {
            vulkan.begin_camera(.{.pos = .{particle_constant.camera.pos[0],-particle_constant.camera.pos[1]}, .zoom = particle_constant.camera.zoom});
            // const thick = UI.theme.line_thick/3;
            // for (0..GRID_CELL_SIDE_COUNT+1) |i| {
            //     const f: f32 = @floatFromInt(i);
            //     draw.rectangle(.{.pos = .{-1,-1+f*GRID_CELL_SIZE-thick/2.0}, .size = .{2,thick}}, .{1,1,1,1});
            //     draw.rectangle(.{.pos = .{-1+f*GRID_CELL_SIZE-thick/2.0,-1}, .size = .{thick,2}}, .{1,1,1,1});
            // }

            // camera_mouse[0] *= vulkan.state.aspect_ratio;

            try vulkan.copy_buffer(staging_buf, grid_offsets_buf, @sizeOf(u32) * GRID_CELL_COUNT);
            const offsets = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(staging_mapped));
            const num_in_bin: u32 = if (m.cell_from_pos(particle_constant.mouse_pos)) |cell| blk: {
                // log.info("camera mouse={}, cell={}", .{camera_mouse, cell});
                const pos = m.splat2(GRID_CELL_SIZE)*@as(V2, @floatFromInt(cell)) + m.splat2(-1);
                draw.rectangle(.{.pos = pos, .size = m.splat2(GRID_CELL_SIZE) }, .{1,0,0,0.2});
                const bin = m.bin_from_cell(cell);
                break :blk offsets[bin];
            } else 0;
            vulkan.end_camera();
            {
                var layout = Layout { .x = 0, .y = -1+UI.theme.padding, .alignment = .center };
                layout.text2(UI.theme.text_scale, annoucement.color, annoucement.text);
                annoucement.update(dt);
            }
            // Right Panel
            {
                var layout = Layout { .x = draw.botright()[0] - 0.01, .y = draw.topleft()[1] + UI.theme.padding, .alignment = .right };
                layout.text_fmt("FPS: {d:.0}", .{1.0/dt});
                layout.text_fmt("Frame Time: {d:.3} ms", .{dt * std.time.ms_per_s});
                layout.text_fmt("(Real: {d:.3} ms)", .{real_dt * std.time.ms_per_s});
                const compute_pass_name = [_][]const u8 {
                    "Grid Offsets",
                    "Prefix Sum",
                    "Sort",
                    "Interaction"
                };
                for (compute_durations, 0..) |d, i| {
                    layout.text_fmt("[{}]{s}: {d:.3} ms", .{ i, compute_pass_name[i], d * std.time.ms_per_s });
                }
                layout.text_fmt("Grid Cell Size: {d:.3}, Count: {}", .{GRID_CELL_SIZE, GRID_CELL_COUNT});
                layout.text_fmt("Particles in bin: {}", .{num_in_bin});
            }
            // Left Panel
            {

                var layout = Layout { .x = draw.topleft()[0] + 0.01, .y = draw.topleft()[1], .alignment = .left };
                const spliter_w = 0.75;
                const title_color = [4]f32 {2,2,2,1};
                const title_scale = UI.theme.text_scale*1.1;

                _ = layout.row(0);
                layout.text2(title_scale, title_color, "Hot Keys"); _ = layout.row(0);
                layout.text("[R]                Regenerate Particles");
                layout.text("[Shift+R]          Randomize Configurations");
                layout.text("[G]                Toggle GUI Overlay");
                layout.text("[Mouse Left/Right] Push/Pull");
                layout.text("[W/A/S/D]          Camera Movement");
                layout.text("[Mouse Whell]      Camera Zoom");

                {
                    layout.spliter(spliter_w);
                    layout.text2(title_scale, title_color, "Live Settings"); _ = layout.row(0);

                    if (layout.check_box(&lock_fps, "Lock FPS") and lock_fps) {
                        particle_constant.dt = 1.0/120.0;
                    }
                    _ = layout.row(0);

                    if (lock_fps) {
                        layout.slide_bar_with_title(f32, b_simulation_dt.min, b_simulation_dt.max, &particle_constant.dt, "Simulation Delta Time: {d:.4} s");
                        _ = layout.row(0);
                    }

                    layout.slide_bar_with_title(f32, b_drag.min, b_drag.max, &particle_constant.drag, "Drag: {d:.4}");
                    _ = layout.row(0);

                    layout.slide_bar_with_title(f32,
                        b_collision_strength.min, b_collision_strength.max,
                        &particle_constant.collision_cfg.strength,
                        "Collision Strength: {d:.4}");
                    _ = layout.row(0);

                    layout.slide_bar_with_title(f32,
                        b_collision_radius.min, b_collision_radius.max,
                        &particle_constant.collision_cfg.radius,
                        "Collision Radius: {d:.5}");
                    _ = layout.row(0);

                    layout.slide_bar_with_title(f32,
                        b_central_strength.min, b_central_strength.max,
                        &particle_constant.central_force,
                        "Central Force: {d:.4}");
                    _ = layout.row(0);
                }

                {
                    layout.spliter(spliter_w);
                    layout.text2(title_scale, title_color, "Particle Generation Settings [R]"); _ = layout.row(0);
                    layout.slide_bar_with_title(u32, 3000, particles.len, &particle_ct, "Particle Count: {}");
                    _ = layout.row(0);
                }

                {
                    layout.spliter(spliter_w);
                    layout.text2(title_scale, title_color, "Configuration Generation Settings [Shift+R]"); _ = layout.row(0);
                    layout.text_fmt("Strength Range: {d:.4}  {d:.4}", .{b_force_strength.min, b_force_strength.max});
                    layout.double_slide_bar(f32,
                        r_force_strength.min, r_force_strength.max,
                        &b_force_strength.min, &b_force_strength.max);
                    _ = layout.row(0);

                    layout.text_fmt("Radius   Range: {d:.4}  {d:.4}", .{b_force_radius.min, b_force_radius.max});
                    layout.double_slide_bar(f32,
                        r_force_radius.min, r_force_radius.max,
                        &b_force_radius.min, &b_force_radius.max);
                    _ = layout.row(0);

                    layout.slide_bar_with_title(u32, 1, MAX_PARTICLE_SPECIE, &config.specie_ct, "Specie Count: {}");
                    _ = layout.row(0);

                    _ = layout.check_box(&always_self_attract, "Always Self Attract");
                }

                layout.spliter(spliter_w);
                const rect_size = [2]f32 {0.05,0.05};
                var   pos = layout.row(rect_size[1]);
                for (0..pre_random_ct) |i| {
                    const rgb = m.rgb_from_hsv(pre_random_specie[i]);
                    draw.rectangle(.{.pos=pos, .size=rect_size}, .{rgb[0],rgb[1],rgb[2],1});
                    pos[0] += UI.theme.padding + rect_size[0];
                }
                pos = layout.row(rect_size[1]);
                for (0..particle_constant.specie_ct) |i| {
                    const rgb = config.species[i].color;
                    draw.rectangle(.{.pos=pos, .size=rect_size}, .{rgb[0],rgb[1],rgb[2],1});
                    pos[0] += UI.theme.padding + rect_size[0];
                }
            }
        }
        vulkan.end_2d();

        try vulkan.end_draw();
        particle_constant.ping_pong = !particle_constant.ping_pong;
    }
    try device.deviceWaitIdle();

    r.RGFW_window_close(window);
    r.RGFW_deinit();
}

const vulkan = @import("vulkan.zig");
const r = @import("RGFW");
const m = @import("math.zig");
const font = @import("font.zig");
const Configuration = @import("configuration.zig");

const std = @import("std");
const log = std.log;
const fatal = std.process.fatal;
const assert = std.debug.assert;
const Camera = vulkan.Camera;
const draw = vulkan.Draw;
const Rect = vulkan.Rect;

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

//
// RGFW Wrappers
//

pub fn get_mouse(win: *r.RGFW_window) V2 {
    var x: i32 = 0;
    var y: i32 = 0;
    _ = r.RGFW_window_getMouse(win, &x, &y);
    return .{@floatFromInt(x), @floatFromInt(y)};
}

pub fn get_mouse_delta() [2]f32 {
    var x: f32 = 0;
    var y: f32 = 0;
    r.RGFW_getMouseVector(&x, &y);
    return .{x,y};
}

pub fn is_mouse_pressed() bool {
    return r.RGFW_isMousePressed(r.RGFW_mouseLeft) != 0;
}

pub fn is_mouse_down() bool {
    return r.RGFW_isMouseDown(r.RGFW_mouseLeft) != 0;
}

pub fn is_mouse_right_down() bool {
    return r.RGFW_isMouseDown(r.RGFW_mouseRight) != 0;
}

pub const Theme = struct {
    line_thick : f32,
    text_color : [4]f32,
    text_scale : f32,
    padding    : f32,
    btn_hover_color_mul  : f32,
    btn_pressed_color_mul: f32,
    slide_bar_w: f32,
    slide_bar_left_spacing: f32,
    slide_bar_right_spacing: f32,
};

pub const UI = struct {
    pressed: bool = false,
    pub const Alignment = enum { left, center, right };
    pub const theme = Theme {
        .line_thick = 0.01,
        .text_color = .{0.8,0.8,0.8,1},
        .text_scale = 2,
        .padding = 0.02,

        .btn_hover_color_mul = 3,
        .btn_pressed_color_mul = 0.7,

        .slide_bar_w = 0.3,
        .slide_bar_left_spacing = 0.15,
        .slide_bar_right_spacing = 0.05,
    };
    pub var frame: struct {
        arena: std.heap.ArenaAllocator = undefined,
        mouse: [2]f32 = .{0,0},
        mouse_delta: [2]f32 = .{0,0},
        mouse_on_ui: bool = false,
    } = .{};

    pub var persistents: std.hash_map.AutoHashMap(*anyopaque, UI) = undefined;

    pub fn init(gpa: std.mem.Allocator) void {
        frame.arena = .init(gpa);
        persistents = .init(gpa);
    }

    pub fn deinit() void {
        frame.arena.deinit();
        persistents.deinit();
    }

    pub fn font_h() f32 {
        return draw.measure_font_h(theme.text_scale);
    }

    pub fn alloc_print(comptime fmt: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(frame.arena.allocator(), fmt, args) catch @panic("OOM");
    }

    pub fn text_fmt(pos: [2]f32, alignment: Alignment, comptime fmt: []const u8, args: anytype) void {
        var layout = Layout { .x=pos[0],.y=pos[1], .alignment = alignment };
        layout.text_fmt(fmt, args);
    }
};

pub const Layout = struct {
    x: f32,
    y: f32,
    alignment: UI.Alignment,

    pub fn row(layout: *Layout, y: f32) [2]f32 {
        const origin_y = layout.y;
        layout.y += y + UI.theme.padding;
        return .{layout.x, origin_y};
    }

    pub fn spliter(layout: *Layout, w: f32) void {
        const spliter_pos = layout.row(UI.theme.line_thick);
        draw.rectangle(.{.pos=spliter_pos, .size = .{w,UI.theme.line_thick}}, UI.theme.text_color);
        _ = layout.row(UI.theme.line_thick);
    }

    pub fn text_fmt(layout: *Layout, comptime fmt: []const u8, args: anytype) void {
        const str = if (args.len == 0) fmt else UI.alloc_print(fmt, args);
        layout.text(str);
    }

    pub fn text(layout: *Layout, str: []const u8) void {
        layout.text2(UI.theme.text_scale, UI.theme.text_color, str);
    }

    pub fn text2(layout: *Layout, scale: f32, color: [4]f32, str: []const u8) void {
        const size = draw.measure_text(str, scale);
        const pos = layout.row(size[1]);

        var aligned_pos = pos;
        switch (layout.alignment) {
            .left => {},
            .center => aligned_pos[0] -= draw.measure_text(str, UI.theme.text_scale)[0]/2,
            .right => aligned_pos[0] -= draw.measure_text(str, UI.theme.text_scale)[0],
        }
        draw.text(aligned_pos, str, scale, color);
    }

    pub fn slide_bar_with_title(layout: *Layout, comptime T: type, left: T, right: T, val: *T, comptime fmt: []const u8) void {
        layout.text_fmt(fmt, .{val.*});
        slide_bar(layout, T, left, right, val);
    }

    pub fn slide_bar(layout: *Layout, comptime T: type, left: T, right: T, val: *T) void {
        const gop = UI.persistents.getOrPut(val) catch @panic("OOM");
        const ui = gop.value_ptr;
        if (!gop.found_existing) {
            ui.* = .{};
        }

        const font_h = UI.font_h();
        var pos = layout.row(font_h);

        UI.text_fmt(pos, .left, "{d:.4}", .{left});
        pos[0] += UI.theme.slide_bar_left_spacing;

        const slide_bar_w = UI.theme.slide_bar_w;
        const slide_rect = Rect {.pos=pos, .size=.{slide_bar_w, font_h}};
        draw.rectangle(slide_rect, .{0.3,0.3,0.3,1});
        slide_bar_btn(T, ui, slide_rect, left, right, left, right, val);
        pos[0] += slide_bar_w + UI.theme.slide_bar_right_spacing;

        UI.text_fmt(pos, .left, "{d:.4}", .{right});
    }

    fn slide_bar_btn(comptime T: type, ui: *UI, slide_rect: Rect, left: T, right: T, clamp_left: T, clamp_right: T, val1: *T) void {
        var i = m.cast(f32, val1.*-left)/m.cast(f32, right-left);

        const pos = slide_rect.pos;
        const slide_bar_w = slide_rect.size[0];
        const slide_btn_size = [2]f32 { slide_bar_w / 8.0, slide_rect.size[1] * 1.5 };

        const btn_rect = Rect.from_center(.{pos[0]+i*slide_bar_w, pos[1]+slide_rect.size[1]/2}, slide_btn_size);
        var btn_color: V4 = UI.theme.text_color;
        if (btn_rect.point_in(UI.frame.mouse) or ui.pressed) {
            UI.frame.mouse_on_ui = true;
            if (is_mouse_down()) {
                ui.pressed = true;
                btn_color = m.color_mul(btn_color, UI.theme.btn_pressed_color_mul);
                i = @max((UI.frame.mouse[0] - slide_rect.pos[0]) / slide_rect.size[0], 0);
                val1.* = m.cast(T, i * m.cast(f32, right-left) + m.cast(f32, left));
                val1.* = std.math.clamp(val1.*, clamp_left, clamp_right);
            } else {
                ui.pressed = false;
                btn_color = m.color_mul(btn_color, UI.theme.btn_hover_color_mul);
            }
        }
        draw.rectangle(btn_rect, btn_color);
    }

    pub fn double_slide_bar(layout: *Layout, comptime T: type, left: T, right: T, val1: *T, val2: *T) void {
        UI.persistents.ensureUnusedCapacity(2) catch @panic("OOM");
        const gop1 = UI.persistents.getOrPut(val1) catch unreachable;
        const ui1 = gop1.value_ptr;
        if (!gop1.found_existing) {
            ui1.* = .{};
        }

        const gop2 = UI.persistents.getOrPut(val2) catch unreachable;
        const ui2 = gop2.value_ptr;
        if (!gop2.found_existing) {
            ui2.* = .{};
        }

        const font_h = UI.font_h();
        var pos = layout.row(font_h);

        UI.text_fmt(pos, .left, "{d:.4}", .{left});
        pos[0] += UI.theme.slide_bar_left_spacing;

        const slide_bar_w = UI.theme.slide_bar_w;
        const slide_rect = Rect {.pos=pos, .size=.{slide_bar_w, font_h}};
        draw.rectangle(slide_rect, .{0.3,0.3,0.3,1});

        slide_bar_btn(T, ui1, slide_rect, left, right, left, val2.* * 0.9, val1);
        slide_bar_btn(T, ui2, slide_rect, left, right, val1.* * 1.1, right, val2);

        pos[0] += slide_bar_w + UI.theme.slide_bar_right_spacing;

        UI.text_fmt(pos, .left, "{d:.4}", .{right});
    }

    pub fn check_box(layout: *Layout, checked: *bool, str: []const u8) bool {
        const font_h = 0.05;
        var pos = layout.row(font_h);
        const size = m.splat2(font_h);
        pos[0] += font_h/2.0;
        const check_box_rec = Rect.from_center(pos, size);
        const outline_check_box_rec = Rect.from_center(pos, size*m.splat2(0.75));
        const inner_check_box_rec = Rect.from_center(pos, size*m.splat2(0.5));
        var color = UI.theme.text_color;
        const hover = check_box_rec.point_in(UI.frame.mouse);
        if (hover) {
            color = m.color_mul(color, UI.theme.btn_hover_color_mul);
        }
        if (!checked.*) {
            color = m.color_mul(color, 0.1);
        }
        draw.rectangle(check_box_rec, m.color_mul(UI.theme.text_color, 0.8));
        draw.rectangle(outline_check_box_rec, .{0,0,0,1});
        draw.rectangle(inner_check_box_rec, color);
        var changed = false;
        if (is_mouse_pressed() and hover) {
            changed = true;
            checked.* = !checked.*;
        }

        pos[0] += font_h/2.0 + UI.theme.padding;
        UI.text_fmt(pos, .left, "{s}", .{str});
        return changed;
    }
};
