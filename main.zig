const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

pub const Particle = extern struct {
    pos: [2]f32,
    color: [3]f32,

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
                .format = .r32g32b32_sfloat,
                .offset = @offsetOf(Particle, "color"),

            }
        };
    }
};

pub const Camera = extern struct {
    pos: [2]f32 = .{0,0},
    zoom: f32 = 1,
};

pub const Push_Constant = extern struct {
    camera: Camera
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io    = init.io;

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
    _ = vulkan.init_queues(device);
    _ = try vulkan.init_swapchain(device);
    _ = try vulkan.init_image_views(arena, device);
    _ = try vulkan.init_shader_modules();
    _ = try vulkan.init_render_pass(device);
    const particles = [_]Particle {
        .{ .pos = .{0,-0.5 }, .color = .{1,0,0,} },
        .{ .pos = .{0.5,0.5  }, .color = .{0,1,0} },
        .{ .pos = .{-0.5,0.5}, .color = .{0,0,1} },
    };
    const particles_size = @sizeOf(Particle) * particles.len;
    _ = try vulkan.init_command_pool(device);
    const vert_buf = try vulkan.create_storage_buffer(particles_size);
    defer vert_buf.destroy();
    {
        const staging_buf = try vulkan.create_staging_buffer(particles_size);
        defer staging_buf.destroy();
        
        const staging_mapped = try vulkan.map_mem(staging_buf.mem, Particle, particles.len);
        @memcpy(staging_mapped, &particles);
        device.unmapMemory(staging_buf.mem);

        try vulkan.copy_buffer(vert_buf, staging_buf, particles_size);
    }

    _ = try vulkan.init_pipeline(@sizeOf(Particle), &Particle.get_input_attrs(0), vert_buf.buf, @sizeOf(Push_Constant));
    _ = try vulkan.init_frame_buffers(arena, device);

    _ = try vulkan.init_command_buffers(device);
    try vulkan.init_sync_primitives(device);

    var camera = Camera {};
    var camera_target = Camera {};
    
    var last_frame = std.Io.Timestamp.now(io, .boot);
    while (r.RGFW_window_shouldClose(window) == 0) {
        const now = std.Io.Timestamp.now(io, .boot);
        const dt = @as(f32, @floatFromInt(last_frame.durationTo(now).nanoseconds)) / std.time.ns_per_s;
        last_frame = now;

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

        const scroll = get_mouse_scroll();
        const wheel = scroll[1];
        camera_target.zoom = std.math.clamp(@exp2(@log2(camera_target.zoom)+wheel*CAMERA_ZOOM_SPD), 0.5, 64.0);

        camera.zoom = exp_smooth(camera.zoom, camera_target.zoom, dt * CAMERA_SMOOTH_SPD);
        camera.pos[0] = exp_smooth(camera.pos[0], camera_target.pos[0], dt * CAMERA_SMOOTH_SPD);
        camera.pos[1] = exp_smooth(camera.pos[1], camera_target.pos[1], dt * CAMERA_SMOOTH_SPD);

        vulkan.set_push_constant(Push_Constant, &.{ .camera = camera });
        try vulkan.draw_frame(@intCast(particles.len * VERT_PER_PARTICLE), vert_buf.buf);
    }
    try device.deviceWaitIdle();

    r.RGFW_window_close(window);
    r.RGFW_deinit();
}

const vulkan = @import("vulkan.zig");
const v = @import("vk.zig");
const r = @import("RGFW");

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
