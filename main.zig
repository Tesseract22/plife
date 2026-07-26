const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

pub const Particle = struct {

};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
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
    defer vulkan.cleanup();
    const device = try vulkan.init_device(arena, WINDOW_W, WINDOW_H);
    _ = vulkan.init_queues(device);
    _ = try vulkan.init_swapchain(device);
    _ = try vulkan.init_image_views(arena, device);
    _ = try vulkan.init_shader_modules();
    _ = try vulkan.init_render_pass(device);
    _ = try vulkan.init_pipeline();
    _ = try vulkan.init_frame_buffers(arena, device);
    _ = try vulkan.init_command_pool(device);
    _ = try vulkan.init_command_buffers(device);
    try vulkan.init_sync_primitives(device);

    // log.info("image_available_sema: {x}, render_finished_sema; {x}", .{image_available_sema, render_finished_sema});

    while (r.RGFW_window_shouldClose(window) == 0) {
        // FIXME: when window resized, we need to recreate swap chain
        r.RGFW_pollEvents();
        vulkan.draw_frame();
        // Waits for last frame to finished, and reset fence
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

