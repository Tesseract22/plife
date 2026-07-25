const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

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
    const instance = try vulkan.init_instance();
    defer vulkan.cleanup();

    //
    // Create Surface
    //
    const surface = try vulkan.init_surface(window);
    defer instance.destroySurfaceKHR(surface, null);

    //
    // Create Logical Device, and Queye Families
    //
    const device = try vulkan.init_device(arena, WINDOW_W, WINDOW_H);
    defer device.destroyDevice(null);
    const graphics_family = vulkan.state.graphics_family;
    const format = vulkan.state.format;
    const extent = vulkan.state.extent;

    const queues = vulkan.init_queues(device);
    const graphics_queue = queues.graphics_queue;
    const present_queue = queues.present_queue;

    const swapchain = try vulkan.init_swapchain(device);
    defer device.destroySwapchainKHR(swapchain, null);

    const image_views = try vulkan.init_image_views(arena, device);
    defer for (image_views) |image_view| device.destroyImageView(image_view, null);

    //
    // Create Graphics Pipeline
    //

    //
    // Create Shader Module
    //
    const vert = try vulkan.create_shader_module(@alignCast(@embedFile("shader.spv")));
    const frag = try vulkan.create_shader_module(@alignCast(@embedFile("shader.spv")));
    defer {
        device.destroyShaderModule(vert, null); device.destroyShaderModule(frag, null);
    }

    const viewport = v.Viewport {
        .x = 0, .y = 0,
        .width = @floatFromInt(extent.width), .height = @floatFromInt(extent.height),
        .min_depth = 0, .max_depth = 1,
    };
    const scissor = v.Rect2D {
        .offset = .{.x=0,.y=0},
        .extent = extent,
    };

    const pipeline_layout, const render_pass,
    const graphics_pipeline = blk: {
        const vert_create_info = v.PipelineShaderStageCreateInfo {
            .stage = .{ .vertex = true },
            .module = vert,
            .p_name = "vert",
        };
        const frag_create_info = v.PipelineShaderStageCreateInfo {
            .stage = .{ .fragment = true },
            .module = frag,
            .p_name = "frag",
        };
        
        const vertex_input_state_info = v.PipelineVertexInputStateCreateInfo {};
        const assembly_state_info = v.PipelineInputAssemblyStateCreateInfo {
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        const viewport_state_info = v.PipelineViewportStateCreateInfo {
            .viewport_count = 1,
            .p_viewports = &.{viewport},
            .scissor_count = 1,
            .p_scissors = &.{scissor},
        };

        const dynamic_states: []const v.DynamicState = &.{
            .viewport,
            .scissor,
        };

        const dynamic_state_info = v.PipelineDynamicStateCreateInfo {
            .dynamic_state_count = @intCast(dynamic_states.len),
            .p_dynamic_states = dynamic_states.ptr,
        };

        const rasteriazation_state_info = v.PipelineRasterizationStateCreateInfo {
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back = true },
            .front_face = .clockwise,

            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        const multi_sample_state_info = v.PipelineMultisampleStateCreateInfo {
            .rasterization_samples = .{ .@"1" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const color_blend_attachment_info = v.PipelineColorBlendAttachmentState {
            .blend_enable = .true,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .@"add",
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .@"add",
            .color_write_mask = .{ .r = true, .g = true, .b = true, .a = true },
        };

        const color_blend_info = v.PipelineColorBlendStateCreateInfo {
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{color_blend_attachment_info},
            .blend_constants = .{0,0,0,0},
        };

        const pipeline_layout = try device.createPipelineLayout(&.{}, null);

        //
        // Create Render Pass
        //
        const color_attachment = v.AttachmentDescription {
            .format = format.format,
            .samples = .{ .@"1" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .present_src_khr,
        };

        const color_attachment_ref = v.AttachmentReference {
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

        const subpass = v.SubpassDescription {
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_ref),
        };

        const subpass_dep = v.SubpassDependency {
            .src_subpass = v.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output = true },
            .dst_access_mask = .{ .color_attachment_write = true },
        };

        const render_pass_info = v.RenderPassCreateInfo {
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_attachment),
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
            .dependency_count = 1,
            .p_dependencies = &.{subpass_dep},
        };

        const render_pass = try device.createRenderPass(&render_pass_info, null);

        const graphics_pipeline_info = v.GraphicsPipelineCreateInfo {
            .stage_count = 2,
            .p_stages = &.{ vert_create_info, frag_create_info },
            .p_vertex_input_state = &vertex_input_state_info,
            .p_input_assembly_state = &assembly_state_info,
            .p_viewport_state = &viewport_state_info,
            .p_rasterization_state = &rasteriazation_state_info,
            .p_multisample_state = &multi_sample_state_info,
            .p_color_blend_state = &color_blend_info,
            .p_dynamic_state = &dynamic_state_info,
            .layout = pipeline_layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_index = -1,
        };
        var graphics_pipeline: [1]v.Pipeline = undefined;
        _ = try device.createGraphicsPipelines(.null_handle, &.{graphics_pipeline_info}, null, &graphics_pipeline);

        break :blk .{ pipeline_layout, render_pass, graphics_pipeline[0] };
    };
    defer {
        device.destroyPipelineLayout(pipeline_layout, null);
        device.destroyRenderPass(render_pass, null);
        device.destroyPipeline(graphics_pipeline, null);
    }

    const frame_buffers = arena.alloc(v.Framebuffer, image_views.len) catch @panic("OOM");
    for (image_views, frame_buffers) |image_view, *frame_buffer| {
        const attachments: []const v.ImageView = &.{
            image_view,
        };
        frame_buffer.* = try device.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = @intCast(attachments.len),
            .p_attachments = attachments.ptr,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        }, null);
    }
    defer for (frame_buffers) |frame_buffer| device.destroyFramebuffer(frame_buffer, null);

    //
    // Command
    //
    const command_pool = try device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer = true },
        .queue_family_index = graphics_family,
    }, null);
    defer device.destroyCommandPool(command_pool, null);

    const MAX_FRAMES_IN_FLIGHT = 3;

    var command_buffers: [MAX_FRAMES_IN_FLIGHT]v.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = MAX_FRAMES_IN_FLIGHT,
    }, &command_buffers);

    //
    // Sync primitives
    //
    var image_available_semas: [MAX_FRAMES_IN_FLIGHT]v.Semaphore = undefined;
    var render_finished_semas: [MAX_FRAMES_IN_FLIGHT]v.Semaphore = undefined;
    var in_flight_fences     : [MAX_FRAMES_IN_FLIGHT]v.Fence = undefined;
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        image_available_semas[i] = try device.createSemaphore(&.{}, null);
        render_finished_semas[i] = try device.createSemaphore(&.{}, null);
        in_flight_fences[i]      = try device.createFence(&.{.flags = .{ .signaled = true }, }, null);
    }
    defer {
        for (image_available_semas) |sema| device.destroySemaphore(sema, null);
        for (render_finished_semas) |sema| device.destroySemaphore(sema, null);
        for (in_flight_fences) |fence| device.destroyFence(fence, null);
    }

    var curr_frame: u32 = 0;

    // log.info("image_available_sema: {x}, render_finished_sema; {x}", .{image_available_sema, render_finished_sema});

    while (r.RGFW_window_shouldClose(window) == 0) {
        // FIXME: when window resized, we need to recreate swap chain
        r.RGFW_pollEvents();

        // Waits for last frame to finished, and reset fence
        _ = try device.waitForFences(&.{in_flight_fences[curr_frame]}, .true, std.math.maxInt(u64));
        try device.resetFences(&.{in_flight_fences[curr_frame]});

        const next_result = try device.acquireNextImageKHR(swapchain, std.math.maxInt(u64), image_available_semas[curr_frame], .null_handle);
        const image_idx = next_result.image_index;

        //
        // Record Command Buffer
        //
        const command_buffer = command_buffers[curr_frame];
        try device.resetCommandBuffer(command_buffer, .{});
        try device.beginCommandBuffer(command_buffer, &.{});
        device.cmdBeginRenderPass(command_buffer, &.{
            .render_pass = render_pass,
            .framebuffer = frame_buffers[image_idx],
            .render_area = .{
                .offset = .{.x=0,.y=0},
                .extent = extent,
            },
            .clear_value_count = 1,
            .p_clear_values = &.{
                .{
                    .color = .{ .float_32 = .{0,0,0,1} },
                }
            },
        }, .@"inline");

        device.cmdBindPipeline(command_buffer, .graphics, graphics_pipeline);

        device.cmdSetViewport(command_buffer, 0, &.{viewport});
        device.cmdSetScissor(command_buffer, 0, &.{scissor});

        device.cmdDraw(command_buffer, 3, 1, 0, 0);
        device.cmdEndRenderPass(command_buffer);
        try device.endCommandBuffer(command_buffer);

        //
        // Submit Command Buffer
        //
        {
            const wait_semas: []const v.Semaphore = &.{
                image_available_semas[curr_frame],
            };
            const signal_semas: []const v.Semaphore = &.{
                render_finished_semas[curr_frame],
            };
            const curr_command_buffers: []const v.CommandBuffer = &.{
                command_buffer,
            };
            try device.queueSubmit(graphics_queue, &.{.{
                .wait_semaphore_count = @intCast(wait_semas.len),
                .p_wait_semaphores = wait_semas.ptr,
                .p_wait_dst_stage_mask = &.{ .{ .color_attachment_output = true } },
                .command_buffer_count = @intCast(curr_command_buffers.len),
                .p_command_buffers = curr_command_buffers.ptr,
                .signal_semaphore_count = @intCast(signal_semas.len),
                .p_signal_semaphores = signal_semas.ptr,
            }}, in_flight_fences[curr_frame]);

            _ = try device.queuePresentKHR(present_queue, &.{
                .wait_semaphore_count = @intCast(signal_semas.len),
                .p_wait_semaphores = signal_semas.ptr,
                .swapchain_count = 1, .p_swapchains = @ptrCast(&swapchain),
                .p_image_indices = @ptrCast(&image_idx),
            });
        }
        curr_frame = (curr_frame + 1) % MAX_FRAMES_IN_FLIGHT;
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

pub fn create_shader_module(device: Device, src: [] align(4) const u8) !v.ShaderModule {
    const u32_slice = std.mem.bytesAsSlice(u32, src);
    const create_info = v.ShaderModuleCreateInfo {
        .code_size = src.len,
        .p_code = u32_slice.ptr,
    };
    return device.createShaderModule(&create_info, null);
}
