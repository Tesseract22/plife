const Vulkan = @This();
const HDR_FORMAT = v.Format.r16g16b16a16_sfloat;
pub const MAX_FRAMES_IN_FLIGHT = 2;
pub const COMPUTE_STAGE_COUNT  = 4;
pub const MAX_TEXTURE          = 4;
pub const MAX_QUERY            = 16;
vkb: v.BaseWrapper = undefined,
instance_handle   : v.Instance = .null_handle,
instance_wrapper  : v.InstanceWrapper = undefined,
instance          : Instance = undefined,

surface           : v.SurfaceKHR = .null_handle,
surface_details   : v.SurfaceCapabilitiesKHR = undefined,
physical_device   : v.PhysicalDevice = .null_handle,

graphics_compute_family   : u32 = undefined,
present_family    : u32 = undefined,


format            : v.SurfaceFormatKHR = undefined,
present_mode      : v.PresentModeKHR = undefined,

extent            : v.Extent2D = undefined,
viewport          : v.Viewport = undefined,
scissor           : v.Rect2D = undefined,
aspect_ratio      : f32 = 1,

physical_device_props : v.PhysicalDeviceProperties = undefined,
device_handle     : v.Device = .null_handle,
device_wrapper    : v.DeviceWrapper = undefined,
device            : Device = undefined,
mem_properties    : v.PhysicalDeviceMemoryProperties = undefined,

graphics_queue    : v.Queue = .null_handle,
present_queue     : v.Queue = .null_handle,
compute_queue     : v.Queue = .null_handle,

swapchain         : v.SwapchainKHR = .null_handle,

shader            : v.ShaderModule = .null_handle,

render_pass       : v.RenderPass = .null_handle,
frame_buffers     : []v.Framebuffer = &.{},
image_views       : []v.ImageView = &.{},

font              : Font.Static = undefined,

hdr_texture       : Texture = .null_handle,
off_screen_render_pass   : v.RenderPass = .null_handle,
hdr_frame_buffer  : v.Framebuffer = .null_handle,
hdr_sampler       : v.Sampler = .null_handle,

query_pool        : v.QueryPool = .null_handle,

particle_desc_set_layout : v.DescriptorSetLayout = .null_handle,
triangle_desc_set_layout : v.DescriptorSetLayout = .null_handle,
particle_pl_layout   : v.PipelineLayout = .null_handle,
triangle_pl_layout   : v.PipelineLayout = .null_handle,
descriptor_pool   : v.DescriptorPool = .null_handle,
particle_desc_set : [MAX_FRAMES_IN_FLIGHT]v.DescriptorSet = .{.null_handle, .null_handle},
// Use the first half of the desc_set for the frame 0, and second half for frame 1
triangle_desc_set : [MAX_FRAMES_IN_FLIGHT * MAX_TEXTURE]v.DescriptorSet = undefined,

graphics_pipeline     : v.Pipeline = .null_handle,
graphics_vert_bufs    : [MAX_FRAMES_IN_FLIGHT]Buffer = .{.null, .null},
graphics_vert_maps    : [MAX_FRAMES_IN_FLIGHT][]Vertex_Data = undefined,
off_screen_graphics_pipeline : v.Pipeline = .null_handle,
compute_pipelines     : [COMPUTE_STAGE_COUNT]v.Pipeline = .{.null_handle, .null_handle, .null_handle, .null_handle},

command_pool               : v.CommandPool = .null_handle,
graphics_command_buffers   : [MAX_FRAMES_IN_FLIGHT]v.CommandBuffer = undefined,
compute_command_buffer     : v.CommandBuffer = .null_handle,

image_available_semas         : [MAX_FRAMES_IN_FLIGHT]v.Semaphore = undefined,
render_finished_semas         : [MAX_FRAMES_IN_FLIGHT]v.Semaphore = undefined,
in_flight_fences              : [MAX_FRAMES_IN_FLIGHT]v.Fence = undefined,

compute_finished_sema         : v.Semaphore = .null_handle,
compute_in_flight_fence       : v.Fence = undefined,

gpa   : Allocator = undefined,
arena : std.heap.ArenaAllocator = undefined,

frame_counter: u32 = 0,

per_frame: struct {
    curr_frame: u32 = 0,
    vertexes: std.ArrayList(Vertex_Data) = .empty,
    vert_ct: u32 = 0,
    triangle_texture_ct: u32 = 0,
    curr_texture: v.ImageView = .null_handle,

    camera: Camera = .init,
    cmd: v.CommandBuffer = .null_handle,
    present_image_idx: u32 = 0,
    curr_compute_stage: ?u32 = null,
    query_ct: u32 = 0,

    durations: [MAX_QUERY/2]f32 = undefined,
} = .{},

pub const Vertex_Data = extern struct {
    pos: [2]f32,
    color: Color,
    tex: [2]f32,

    pub fn get_input_attrs(binding: u32) [3]v.VertexInputAttributeDescription {
        return .{
            .{
                .location = 0,
                .binding = binding,
                .format = .r32g32_sfloat,
                .offset = @offsetOf(Vertex_Data, "pos"),
            },
            .{
                .location = 1,
                .binding = binding,
                .format = .r32g32b32a32_sfloat,
                .offset = @offsetOf(Vertex_Data, "color"),

            },
            .{
                .location = 2,
                .binding = binding,
                .format = .r32g32_sfloat,
                .offset = @offsetOf(Vertex_Data, "tex"),

            },


        };
    }
};

pub const Texture = struct {
    image: v.Image,
    view : v.ImageView,
    mem  : v.DeviceMemory,

    pub const null_handle = Texture { .image = .null_handle, .view = .null_handle, .mem = .null_handle };
};
// pub fn init_window(w: u32, h: u32, name: []const u8) void {
//
// }
pub var state = Vulkan {};
const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

pub fn init_instance(gpa: Allocator) !void {
    state.gpa = gpa;
    state.arena = .init(gpa);

    state.vkb = v.BaseWrapper.load(vkGetInstanceProcAddr);
    var app_info = v.ApplicationInfo {
        .application_version = @bitCast(v.API_VERSION_1_2),
        .engine_version = @bitCast(v.API_VERSION_1_2),
        .api_version = @bitCast(v.API_VERSION_1_2),
    };
    app_info.p_application_name = "Hello Triangle";
    app_info.p_engine_name = "No Engine";

    var create_info = v.InstanceCreateInfo {};
    create_info.p_application_info = &app_info;
    create_info.enabled_layer_count = 1;
    const layers: []const [*:0]const u8 = if (@import("builtin").optimize == .debug) &.{"VK_LAYER_KHRONOS_validation"} else &.{};
    std.log.info("enabled layers={}", .{layers.len});
    create_info.pp_enabled_layer_names = layers.ptr;
    create_info.enabled_layer_count = @intCast(layers.len);
    // var required_extension_count: u32 = undefined;
    // const required_extensions = r.RGFW_getRequiredInstanceExtensions_Vulkan(&required_extension_count);
    // if (!required_extensions) {
    //     fatal(
    //         \\RGFW_getRequiredInstanceExtensions_Vulkan failed to find the
    //         \\platform surface extensions.\n\nDo you have a compatible
    //         \\Vulkan installable client driver (ICD) installed?\nPlease
    //         \\look at the Getting Started guide for additional
    //         \\information.\n",
    //         \\vkCreateInstance Failure"
    //         ,.{});
    // }
    // FIXME: #platform
    const extensions: []const [*:0]const u8 = &.{
        v.extensions.khr_surface.name,
        v.extensions.khr_win_32_surface.name,
    };
    create_info.enabled_extension_count = extensions.len;
    create_info.pp_enabled_extension_names = extensions.ptr;
    const handle = try state.vkb.createInstance(&create_info, null);

    state.instance_handle = handle;
    state.instance_wrapper = .load(handle, vkGetInstanceProcAddr);
    state.instance = .init(handle, &state.instance_wrapper);
}

pub fn init_surface(window: *r.RGFW_window) !void {
    // FIXME: #platform
    const create_info = v.Win32SurfaceCreateInfoKHR {
        .hwnd = @ptrCast(r.RGFW_window_getHWND(window)),
        .hinstance = @ptrCast(r.RGFW_window_getHINSTANCE()),
    };
    state.surface = try state.instance.createWin32SurfaceKHR(&create_info, null);
}

pub fn is_device_good(device: v.PhysicalDevice) bool {
    const instance = state.instance;
    // const properties = instance.getPhysicalDeviceProperties(device);
    // const features   = instance.getPhysicalDeviceFeatures(device);

    var vulkan11_features = v.PhysicalDeviceVulkan11Features{
        .s_type = .physical_device_vulkan_1_1_features,
    };
    var features2 = v.PhysicalDeviceFeatures2 {
        .s_type = .physical_device_features_2,
        .p_next = &vulkan11_features,
        .features = .{},
    };
    instance.getPhysicalDeviceFeatures2(device, &features2);

    return vulkan11_features.variable_pointers == .true;
}

pub fn init_device(window_width: u32, window_height: u32) !Device {
    const arena = state.arena.allocator();
    var device_count: u32 = 0;
    _ = try state.instance.enumeratePhysicalDevices(&device_count, null);
    log.info("found {} devices: ", .{device_count});
    if (device_count == 0) @panic("no devic found");
    const devices = try arena.alloc(v.PhysicalDevice, device_count);
    _ = try state.instance.enumeratePhysicalDevices(&device_count, devices.ptr);
    state.physical_device = devices[0];
    assert(is_device_good(state.physical_device));

    var queue_family_count: u32 = 0;
    state.instance.getPhysicalDeviceQueueFamilyProperties(state.physical_device, &queue_family_count, null);
    log.info("found {} queue family", .{queue_family_count});
    const families = try arena.alloc(v.QueueFamilyProperties, queue_family_count);
    state.instance.getPhysicalDeviceQueueFamilyProperties(state.physical_device, &queue_family_count, families.ptr);
    var graphics_family: ?u32 = null; // we need a queue for both graphics and compute
    var present_family : ?u32 = null;
    for (0..queue_family_count) |i| {
        if (families[i].queue_flags.graphics and families[i].queue_flags.compute) 
            graphics_family = @intCast(i);
        if (try state.instance.getPhysicalDeviceSurfaceSupportKHR(state.physical_device, @intCast(i), state.surface) == .true)
            present_family = @intCast(i);
    }
    if (graphics_family == null) @panic("cannot found graphics family queue");
    if (present_family == null) @panic("cannot found present family queue");
    state.graphics_compute_family = graphics_family.?;
    state.present_family = present_family.?;

    const priority: []const f32 = &.{1};
    const device_queue_create_infos: []const v.DeviceQueueCreateInfo = &.{
        .{
            .queue_family_index = state.graphics_compute_family,
            .queue_count = 1,
            .p_queue_priorities = priority.ptr,
        },
        .{
            .queue_family_index = state.present_family,
            .queue_count = 1,
            .p_queue_priorities = priority.ptr,
        },
    };
    const device_feature = v.PhysicalDeviceFeatures {
        .sampler_anisotropy = .true,
    };
    const extensions: []const [*:0]const u8 = &.{
        v.extensions.khr_swapchain.name,
    };
    var enabled_vulkan11_features = v.PhysicalDeviceVulkan11Features{
        .variable_pointers = .true,
        .variable_pointers_storage_buffer = .true, // enable both to be safe
    };

    const device_create_info = v.DeviceCreateInfo {
        .p_next = &enabled_vulkan11_features,
        .p_queue_create_infos = device_queue_create_infos.ptr,
        .queue_create_info_count = @intCast(device_queue_create_infos.len),
        .p_enabled_features = &device_feature,
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_extension_count = extensions.len,
    };

    state.surface_details = try state.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(state.physical_device, state.surface);
    var format_count: u32 = 0;
    _ = try state.instance.getPhysicalDeviceSurfaceFormatsKHR(state.physical_device, state.surface, &format_count, null);
    if (format_count == 0) @panic("no format found");
    log.info("found {} supported format", .{format_count});
    const formats = try arena.alloc(v.SurfaceFormatKHR, format_count);
    _ = try state.instance.getPhysicalDeviceSurfaceFormatsKHR(state.physical_device, state.surface, &format_count, formats.ptr);

    var present_mode_count: u32 = 0;
    _ = try state.instance.getPhysicalDeviceSurfacePresentModesKHR(state.physical_device, state.surface, &present_mode_count, null);
    if (present_mode_count == 0) @panic("no present mode found");
    log.info("found {} present mode", .{present_mode_count});
    const present_modes = try arena.alloc(v.PresentModeKHR, present_mode_count);
    _ = try state.instance.getPhysicalDeviceSurfacePresentModesKHR(state.physical_device, state.surface, &present_mode_count, present_modes.ptr);

    state.format = for (formats) |format| {
        // FIXME: hacky way to do HDR
        if (format.format == .r8g8b8a8_srgb and format.color_space == .srgb_nonlinear_khr) break format;
    } else formats[0];
    state.present_mode = for (present_modes) |present_mode| {
        if (present_mode == .mailbox_khr) break present_mode;
    } else .fifo_khr;
    state.extent =
        if (state.surface_details.current_extent.width != std.math.maxInt(u32))
            state.surface_details.current_extent
        else
            v.Extent2D {
                .width = std.math.clamp(window_width, state.surface_details.min_image_extent.width, state.surface_details.max_image_extent.width),
                .height = std.math.clamp(window_height, state.surface_details.min_image_extent.height, state.surface_details.max_image_extent.height),
            };
    state.aspect_ratio = @as(f32, @floatFromInt(state.extent.width)) / @as(f32, @floatFromInt(state.extent.height));
    log.info("window width={}, height={}, aspect_ratio={}", .{ state.extent.width, state.extent.height, state.aspect_ratio });

    state.device_handle = try state.instance.createDevice(state.physical_device, &device_create_info, null);
    state.device_wrapper = v.DeviceWrapper.load(state.device_handle, state.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    assert(state.device_wrapper.dispatch.vkCreateGraphicsPipelines != null);
    state.device = Device.init(state.device_handle, &state.device_wrapper);

    state.viewport = .{
        .x = 0, .y = 0,
        .width = @floatFromInt(state.extent.width),
        .height = @floatFromInt(state.extent.height),
        .min_depth = 0, .max_depth = 1,
    };
    state.scissor = .{
        .offset = .{.x=0,.y=0},
        .extent = state.extent,
    };

    state.mem_properties =
        state.instance.getPhysicalDeviceMemoryProperties(state.physical_device);

    state.query_pool = try state.device.createQueryPool(&.{
        .query_type = .timestamp,
        .query_count = MAX_QUERY,
    }, null);
    return state.device;
}

pub const Queues = struct {
    graphics_queue: v.Queue,
    present_queue: v.Queue,
};

pub fn init_font() !void {
    state.font = try .init(@embedFile("./home-video.regular.ttf"), 0, 128, .{256,256}, 30, state.gpa);
}

pub fn init_queues(device: Device) void {
    state.graphics_queue = device.getDeviceQueue(state.graphics_compute_family, 0);
    state.present_queue = state.graphics_queue;
    // state.present_queue  = device.getDeviceQueue(state.present_family, 0);
    state.compute_queue  = device.getDeviceQueue(state.graphics_compute_family, 0);
}

pub fn init_swapchain(device: Device) !void {
    const image_count = state.surface_details.min_image_count;
    assert(state.surface_details.max_image_count != 0 and image_count <= state.surface_details.max_image_count);

    var create_info = v.SwapchainCreateInfoKHR {
        .surface = state.surface,
        .min_image_count = image_count,
        .image_format = state.format.format,
        .image_color_space = state.format.color_space,
        .image_extent = state.extent,
        .image_array_layers = 1,
        .present_mode = state.present_mode,
        .clipped = .true,
        .image_usage = .{ .color_attachment = true },
        .pre_transform = state.surface_details.current_transform,
        .composite_alpha = .{ .opaque_khr = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
        .old_swapchain = .null_handle,
    };
    if (state.graphics_compute_family != state.present_family) {
        log.info("different queue", .{});
        create_info.image_sharing_mode = .concurrent;
        create_info.queue_family_index_count = 2;
        create_info.p_queue_family_indices = &.{ state.graphics_compute_family, state.present_family };
    }

    state.swapchain = try device.createSwapchainKHR(&create_info, null);
}

pub fn create_texture(format: v.Format, w: u32, h: u32, usage: v.ImageUsageFlags, layout: v.ImageLayout, swizzle: ?v.ComponentMapping) !Texture {
    const device = state.device;
    const image = try device.createImage(&.{
           .image_type = .@"2d",
           .format = format,
           .extent = .{ .width = w, .height = h, .depth = 1 },
           .mip_levels = 1,
           .array_layers = 1,
           .samples = .{ .@"1" = true },
           .tiling = .optimal,
           .usage = usage,
           .sharing_mode = .exclusive,
           .initial_layout = layout,
    }, null);

    const mem_reqs = device.getImageMemoryRequirements(image);
    const mem_type = find_mem_type(mem_reqs.memory_type_bits, .{ .device_local = true });
    const mem = try device.allocateMemory(&.{
            .allocation_size = mem_reqs.size,
            .memory_type_index = mem_type,
    }, null);
    try device.bindImageMemory(image, mem, 0);
    const view = try device.createImageView(&.{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = swizzle orelse .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = .{
            .aspect_mask = .{ .color = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    return Texture {
        .image = image,
        .view  = view,
        .mem   = mem,
    };
}

pub fn init_image_views(device: Device) !void {
    const arena = state.arena.allocator();
    var image_count: u32 = 0;
    _ = try device.getSwapchainImagesKHR(state.swapchain, &image_count, null);
    log.info("swapchain image: {}", .{image_count});
    const images = try arena.alloc(v.Image, image_count);
    _ = try device.getSwapchainImagesKHR(state.swapchain, &image_count, images.ptr);

    state.image_views = try arena.alloc(v.ImageView, image_count);
    for (images, 0..) |image, i| {
        const create_info = v.ImageViewCreateInfo {
            .image = image,
            .view_type = .@"2d",
            .format = state.format.format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };
        state.image_views[i] = try device.createImageView(&create_info, null);
    }
    state.hdr_texture = try create_texture(
        HDR_FORMAT,
        state.extent.width, state.extent.height,
        .{ .color_attachment = true, .sampled = true },
        .@"undefined", null);
    state.physical_device_props = state.instance.getPhysicalDeviceProperties(state.physical_device);
    state.hdr_sampler = try device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .anisotropy_enable = .true,
        .max_anisotropy = state.physical_device_props.limits.max_sampler_anisotropy,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = 0,
        .min_lod = 0,
        .max_lod = 0,
    }, null);
}

pub fn cleanup() void {
    const device = state.device;
    const instance = state.instance;

    for (state.image_available_semas) |sema|
        device.destroySemaphore(sema, null);
    for (state.render_finished_semas) |sema|
        device.destroySemaphore(sema, null);
    for (state.in_flight_fences) |fence|
        device.destroyFence(fence, null);
    for (state.compute_finished_semas) |sema|
        device.destroySemaphore(sema, null);
    device.destroyFence(state.compute_in_flight_fence, null);

    device.destroyDescriptorPool(state.descriptor_pool, null);
    device.destroyCommandPool(state.command_pool, null);

    device.destroyDescriptorSetLayout(state.particle_desc_set_layout, null);
    device.destroyDescriptorSetLayout(state.triangle_desc_set_layout, null);
    device.destroyPipelineLayout(state.particle_pl_layout, null);
    device.destroyPipelineLayout(state.triangle_pl_layout, null);
    device.destroyRenderPass(state.render_pass, null);
    device.destroyRenderPass(state.off_screen_render_pass, null);
    device.destroyPipeline(state.graphics_pipeline, null);
    for (state.graphics_vert_bufs) |buf| {
        device.unmapMemory(buf.mem);
        buf.destroy();
    }

    device.destroyPipeline(state.off_screen_graphics_pipeline, null);
    for (state.compute_pipelines) |pipeline|
        device.destroyPipeline(pipeline, null);

    for (state.frame_buffers) |frame_buffer|
        device.destroyFramebuffer(frame_buffer, null);

    device.destroyShaderModule(state.shader, null);
    for (state.image_views) |image_view|
        device.destroyImageView(image_view, null);
    device.destroyImage(state.hdr_image, null);
    device.destroyImageView(state.hdr_image_view, null);
    device.freeMemory(state.hdr_image_mem, null);
    device.destroyFramebuffer(state.hdr_frame_buffer, null);
    device.destroySampler(state.hdr_sampler, null);

    device.destroySwapchainKHR(state.swapchain, null);

    device.destroyQueryPool(state.query_pool, null);
    device.destroyDevice(null);

    instance.destroySurfaceKHR(state.surface, null);
    instance.destroyInstance(null);

    state.arena.deinit();
}


const v = @import("thirdparty/vk.zig");
const r = @import("RGFW");
const m = @import("math.zig");
const Font = @import("font.zig");

const Instance = v.InstanceProxy;
const Device = v.DeviceProxy;

const std = @import("std");
const log = std.log;
const fatal = std.process.fatal;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn create_shader_module(src: []align(4) const u8) !v.ShaderModule {
    const u32_slice = std.mem.bytesAsSlice(u32, src);
    const create_info = v.ShaderModuleCreateInfo {
        .code_size = src.len,
        .p_code = u32_slice.ptr,
    };
    return state.device.createShaderModule(&create_info, null);
}

pub fn init_shader_modules() !void {
    state.shader = try create_shader_module(@alignCast(@embedFile("shader.spv")));
}

pub const Render_Pass_Options = struct {
    format: v.Format,
    off_screen: bool = false,
};

pub fn create_render_pass(opts: Render_Pass_Options) !v.RenderPass {
    const device = state.device;
    const color_attachment = v.AttachmentDescription{
        .format = opts.format,
        .samples = .{ .@"1" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .@"undefined",
        .final_layout =
            if (opts.off_screen)
                .shader_read_only_optimal
            else
                .present_src_khr
    };

    const color_ref = v.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = v.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_ref),
    };

    const dependency = v.SubpassDependency{
        .src_subpass = v.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output = true },
        .dst_access_mask = .{ .color_attachment_write = true },
    };

    const render_pass_info = v.RenderPassCreateInfo{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&dependency),
    };

    return device.createRenderPass(&render_pass_info, null);
}

pub fn init_hdr_render_pass() !void {
    state.off_screen_render_pass = try create_render_pass(.{
        .format = HDR_FORMAT,
        .off_screen = true,
    });
    state.hdr_frame_buffer = try state.device.createFramebuffer(&.{
        .render_pass = state.off_screen_render_pass,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&state.hdr_texture.view),
        .width = state.extent.width,
        .height = state.extent.height,
        .layers = 1,
    }, null);
}

pub fn init_render_pass() !void {
    state.render_pass = try create_render_pass(.{
        .off_screen = false,
        .format     = state.format.format,
    });
}

pub fn init_frame_buffers(arena: std.mem.Allocator, device: Device) !void {
    state.frame_buffers = try arena.alloc(v.Framebuffer, state.image_views.len);
    for (state.image_views, state.frame_buffers) |image_view, *frame_buffer| {
        const attachments: []const v.ImageView = &.{image_view};
        frame_buffer.* = try device.createFramebuffer(&.{
            .render_pass = state.render_pass,
            .attachment_count = @intCast(attachments.len),
            .p_attachments = attachments.ptr,
            .width = state.extent.width,
            .height = state.extent.height,
            .layers = 1,
        }, null);
    }
}

pub fn write_texture_to_descriptor(idx: u32, texture: v.ImageView) void {
    const writes = [_]v.WriteDescriptorSet {
        .{
            .dst_set = state.triangle_desc_set[idx],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            
            .p_image_info = &.{
                .{
                    .image_layout = .shader_read_only_optimal,
                        .sampler = state.hdr_sampler,
                        .image_view = texture,
                }
            },

            .p_buffer_info = &.{},
            .p_texel_buffer_view = &.{},
        }
    };
    state.device.updateDescriptorSets(&writes, null);
}

// Descriptor Set describes how storage buffer etc. is accessed in shaders
pub fn init_particle_desc_set(
    ping_pong: [MAX_FRAMES_IN_FLIGHT]v.Buffer,
    grid_offsets: v.Buffer,
    grid_offsets_prefix: v.Buffer, grid_offsets_prefix_copy: v.Buffer,
    part_sorted: v.Buffer, force_configs: v.Buffer, species: v.Buffer) !void {
    const device = state.device;
    const bindings = [_]v.DescriptorSetLayoutBinding{
        .{ // particles ping buffer
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex = true, .compute = true },
        },
        .{ // particles pong buffer
            .binding = 1,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex = true, .compute = true },
        },
        .{ // grid offsets buffer
            .binding = 2,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true },
        },
        .{ // grid offsets prefix buffer
            .binding = 3,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true }, // TODO: remove vertex bit
        },
        .{ // grid offsets prefix buffer
            .binding = 4,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true },
        },
        .{ // particles sorted
            .binding = 5,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true },
        },
        .{ // force configs
            .binding = 6,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true },
        },
        .{ // species
            .binding = 7,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex  = true, .compute = true },
        },
    };

    state.particle_desc_set_layout = try state.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(bindings.len),
        .p_bindings = &bindings,
    }, null);

    const pool_sizes = [_]v.DescriptorPoolSize {
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },
        .{
            .type = .storage_buffer,
            .descriptor_count = 2,
        },

        .{
            .type = .combined_image_sampler,
            .descriptor_count = MAX_TEXTURE * MAX_FRAMES_IN_FLIGHT,
        }
    };
    state.descriptor_pool = try device.createDescriptorPool(&.{
        .max_sets = state.particle_desc_set.len + state.triangle_desc_set.len,
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes
    }, null);
    // defer device.destroyDescriptorPool(state.descriptor_pool, null);

    // Allocate
    try device.allocateDescriptorSets(&.{
        .descriptor_pool = state.descriptor_pool,
            .descriptor_set_count = MAX_FRAMES_IN_FLIGHT,
            .p_set_layouts = &.{state.particle_desc_set_layout, state.particle_desc_set_layout}, // same layout for both set
    }, &state.particle_desc_set);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        // Write buffer references into the set
        const ssbo_info = [_]v.DescriptorBufferInfo {.
            {
                .buffer = ping_pong[i],
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = ping_pong[(i+1)%MAX_FRAMES_IN_FLIGHT],
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = grid_offsets,
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = grid_offsets_prefix,
                    .offset = 0,
                    .range = v.WHOLE_SIZE,
            },

            .{
                .buffer = grid_offsets_prefix_copy,
                    .offset = 0,
                    .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = part_sorted,
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = force_configs,
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
            .{
                .buffer = species,
                .offset = 0,
                .range = v.WHOLE_SIZE,
            },
        };
        
        const writes = [_]v.WriteDescriptorSet {
            .{
                .dst_set = state.particle_desc_set[i],
                    .dst_binding = 0,
                    .dst_array_element = 0,
                    .descriptor_count = ssbo_info.len,
                    .descriptor_type = .storage_buffer,
                    .p_buffer_info = &ssbo_info,
                    
                    .p_image_info = &.{},
                    .p_texel_buffer_view = &.{},
            },
        };
        
        device.updateDescriptorSets(&writes, null);
    }
}

pub fn init_triangle_desc_set() !void {
    const device = state.device;
    const bindings = [_]v.DescriptorSetLayoutBinding{
        .{ // texture
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment = true },
        }
    };

    state.triangle_desc_set_layout = try state.device.createDescriptorSetLayout(&.{
        .binding_count = @intCast(bindings.len),
        .p_bindings = &bindings,
    }, null);

    var layout: [MAX_FRAMES_IN_FLIGHT * MAX_TEXTURE]v.DescriptorSetLayout = undefined;
    @memset(&layout, state.triangle_desc_set_layout);
    // Allocate
    try device.allocateDescriptorSets(&.{
        .descriptor_pool = state.descriptor_pool,
            .descriptor_set_count = state.triangle_desc_set.len,
            .p_set_layouts = &layout, // same layout for both set
    }, &state.triangle_desc_set);
    // Writing buffer references is done per frame
}

pub fn init_pipeline_layout(particle_constant_size: usize) !void {
    state.particle_pl_layout = try state.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = &.{state.particle_desc_set_layout},
        .push_constant_range_count = 1,
        .p_push_constant_ranges =
            if (particle_constant_size > 0) &.{ .{
                .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
                .offset = 0,
                .size = @intCast(particle_constant_size),
            }} else &.{}
    }, null);

    state.triangle_pl_layout = try state.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = &.{state.triangle_desc_set_layout},
        .push_constant_range_count = 1,
        .p_push_constant_ranges = &.{.{
            .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
            .offset = 0,
            .size = @sizeOf(Triangle_Constant),
        }}
    }, null);

}

pub const Blend_Mode = enum {
    normal,
    additive,
};

pub const Pipeline_Options = struct {
    vert_shader_name: [:0]const u8,
    frag_shader_name: [:0]const u8,
    vert_input_stride: usize = 0,
    vert_input_attrs: []const v.VertexInputAttributeDescription = &.{},
    blend_mode: Blend_Mode = .normal,
    render_pass: v.RenderPass,
    layout: v.PipelineLayout,
};

fn create_pipeline(opts: Pipeline_Options) !v.Pipeline {
    const vert_create_info = v.PipelineShaderStageCreateInfo {
        .stage = .{ .vertex = true },
        .module = state.shader,
        .p_name = opts.vert_shader_name,
    };
    const frag_create_info = v.PipelineShaderStageCreateInfo {
        .stage = .{ .fragment = true },
        .module = state.shader,
        .p_name = opts.frag_shader_name,
    };

    //
    // Vertex Input
    //
    const vertex_binding_desc = v.VertexInputBindingDescription {
        .binding    = 0,
        .stride     = @intCast(opts.vert_input_stride),
        .input_rate = .vertex,
    };

    const vertex_input_state_info = v.PipelineVertexInputStateCreateInfo {
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = &.{vertex_binding_desc},
        .vertex_attribute_description_count = @intCast(opts.vert_input_attrs.len),
        .p_vertex_attribute_descriptions = opts.vert_input_attrs.ptr,

    };
    const assembly_state_info = v.PipelineInputAssemblyStateCreateInfo {
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const viewport_state_info = v.PipelineViewportStateCreateInfo {
        .viewport_count = 1,
        .p_viewports = &.{state.viewport},
        .scissor_count = 1,
        .p_scissors = &.{state.scissor},
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

    const color_blend_attachment_info = switch (opts.blend_mode) {
        .normal => v.PipelineColorBlendAttachmentState {
            .blend_enable = .true, // TODO: ????
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .@"add",
            .src_alpha_blend_factor = .one_minus_src_alpha,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .@"add",
            .color_write_mask = .{ .r = true, .g = true, .b = true, .a = true },
        },
        .additive => v.PipelineColorBlendAttachmentState {
            .blend_enable = .true,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one,
            .color_blend_op = .@"add",
            .src_alpha_blend_factor = .src_alpha,
            .dst_alpha_blend_factor = .dst_alpha,
            .alpha_blend_op = .@"add",
            .color_write_mask = .{ .r = true, .g = true, .b = true, .a = true },
        }
    };

    const color_blend_info = v.PipelineColorBlendStateCreateInfo {
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &.{color_blend_attachment_info},
        .blend_constants = .{0,0,0,0},
    };

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
        .layout = opts.layout,
        .render_pass = opts.render_pass,
        .subpass = 0,
        .base_pipeline_index = -1,
    };
    var pipeline: v.Pipeline = .null_handle;
    _ = try state.device.createGraphicsPipelines(.null_handle, &.{graphics_pipeline_info}, null, @ptrCast(&pipeline));
    return pipeline;
}

pub fn init_pipeline() !void {
    state.graphics_pipeline = try create_pipeline(.{
        .vert_shader_name  = "vert_hdr",
        .frag_shader_name  = "frag_hdr",
        .vert_input_stride = @sizeOf(Vertex_Data),
        .vert_input_attrs  = &Vertex_Data.get_input_attrs(0),
        .render_pass       = state.render_pass,
        .layout            = state.triangle_pl_layout,
    });
    const MAX_VERT_LEN = 1 << 16;
    for (&state.graphics_vert_bufs, &state.graphics_vert_maps) |*buf, *map| {
        buf.* = try create_buffer(
            MAX_VERT_LEN*@sizeOf(Vertex_Data),
            .{ .transfer_dst = true, .vertex_buffer = true },
            .{ .host_visible = true, .host_coherent = true });
        map.* = try map_mem(buf.mem, Vertex_Data, MAX_VERT_LEN);
    }
}

pub fn init_off_screen_pipeline() !void {
    state.off_screen_graphics_pipeline = try create_pipeline(.{
        .vert_shader_name = "vert",
        .frag_shader_name = "frag",
        .blend_mode = .additive,
        .render_pass = state.off_screen_render_pass,
        .layout = state.particle_pl_layout,
    });
}

pub fn init_compute_pipeline() !void {
    const device = state.device;

    const compute_shader_infos = [COMPUTE_STAGE_COUNT]v.PipelineShaderStageCreateInfo {
        .{
            .stage = .{ .compute = true },
            .module = state.shader,
            .p_name = "compute_grid_offsets",
        },
        .{
            .stage = .{ .compute = true },
            .module = state.shader,
            .p_name = "compute_offset_prefix",
        },
        .{
            .stage = .{ .compute = true },
            .module = state.shader,
            .p_name = "sort_particles",
        },
        .{
            .stage = .{ .compute = true },
            .module = state.shader,
            .p_name = "compute",
        },
        
    };
    const create_infos = [COMPUTE_STAGE_COUNT]v.ComputePipelineCreateInfo {
        .{
            .layout = state.particle_pl_layout,
            .stage  = compute_shader_infos[0],
            .base_pipeline_index = -1,
        },
        .{
            .layout = state.particle_pl_layout,
            .stage  = compute_shader_infos[1],
            .base_pipeline_index = -1,
        },
        .{
            .layout = state.particle_pl_layout,
            .stage  = compute_shader_infos[2],
            .base_pipeline_index = -1,
        },
        .{
            .layout = state.particle_pl_layout,
            .stage  = compute_shader_infos[3],
            .base_pipeline_index = -1,
        }
    };
    _ = try device.createComputePipelines(.null_handle, &create_infos, null, &state.compute_pipelines);
}

pub fn init_command_pool(device: Device) !v.CommandPool {
    state.command_pool = try device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer = true },
        .queue_family_index = state.graphics_compute_family,
    }, null);
    return state.command_pool;
}

pub const CommandBuffers = [MAX_FRAMES_IN_FLIGHT]v.CommandBuffer;

pub fn init_command_buffers(device: Device) !void {
    try device.allocateCommandBuffers(&.{
        .command_pool = state.command_pool,
        .level = .primary,
        .command_buffer_count = MAX_FRAMES_IN_FLIGHT,
    }, &state.graphics_command_buffers);
    try device.allocateCommandBuffers(&.{
        .command_pool = state.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&state.compute_command_buffer));
}

pub fn find_mem_type(filter: u32, properties: v.MemoryPropertyFlags) u32 {
    for (0..state.mem_properties.memory_type_count) |i| {
        if (filter & (@as(usize, 1) << @intCast(i)) != 0 and
            state.mem_properties.memory_types[i].property_flags.intersect(properties).contains(properties)) {
            return @intCast(i);
        }
    } else @panic("no suitable memory type found");
}

pub const Buffer = struct {
    buf: v.Buffer,
    mem: v.DeviceMemory,

    pub const @"null" = Buffer { .buf = .null_handle, .mem = .null_handle };

    pub fn destroy(self: Buffer) void {
        state.device.destroyBuffer(self.buf, null);
        state.device.freeMemory(self.mem, null);
    }
};

pub fn create_buffer(size: usize, usage: v.BufferUsageFlags, properties: v.MemoryPropertyFlags) !Buffer {
    const device = state.device;
    const buf = try device.createBuffer(&.{
        .size = @intCast(size),
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null);

    // Allocate Device Memory
    const requiremenst = device.getBufferMemoryRequirements(buf);
    const mem_type = find_mem_type(requiremenst.memory_type_bits, properties);
    const device_mem = try device.allocateMemory(&.{
        .allocation_size = requiremenst.size,
        .memory_type_index = mem_type,
    }, null);

    try device.bindBufferMemory(buf, device_mem, 0);
    return .{
        .buf = buf,
        .mem = device_mem,
    };
}

pub fn create_staging_buffer(size: usize) !Buffer {
    return create_buffer(size, .{ .transfer_src = true, .transfer_dst = true }, .{ .host_visible = true, .host_coherent = true });
}

pub fn create_storage_buffer(size: usize, vertex: bool) !Buffer {
    return create_buffer(size, .{ .transfer_dst = true, .vertex_buffer = vertex, .storage_buffer = true }, .{ .device_local = true });
}

pub fn create_vertex_buffer(size: usize) !Buffer {
    return create_buffer(size, .{ .transfer_dst = true, .vertex_buffer = true }, .{ .device_local = true });
}

pub fn begin_tmp_cmd() !v.CommandBuffer {
    const device = state.device;
    var cmd: v.CommandBuffer = .null_handle;
    try device.allocateCommandBuffers(&.{
       .level = .primary,
       .command_pool = state.command_pool,
       .command_buffer_count = 1,
    }, @ptrCast(&cmd));

    try device.beginCommandBuffer(cmd, &.{
        .flags = .{ .one_time_submit = true },
    });
    return cmd;
}

pub fn end_tmp_cmd(cmd: v.CommandBuffer) !void {
    const device = state.device;
    try device.endCommandBuffer(cmd);

    try device.queueSubmit(state.graphics_queue, &.{
        .{ .command_buffer_count = 1, .p_command_buffers = &.{cmd} }
    }, .null_handle);
    try device.queueWaitIdle(state.graphics_queue);

    device.freeCommandBuffers(state.command_pool, &.{cmd});
}

pub fn copy_buffer(dst: Buffer, src: Buffer, size: usize) !void {
    const device = state.device;
    const cmd = try begin_tmp_cmd();
    device.cmdCopyBuffer(cmd, src.buf, dst.buf, &.{
        .{ .src_offset = 0, .dst_offset = 0, .size = size },
    });
    try end_tmp_cmd(cmd);
}

pub fn copy_to_bytes(mapped: []u8, data: anytype) u32 {
    const len = data.len;
    const info = @typeInfo(@TypeOf(data));
    const T = switch (info) {
        .pointer => |ptr| ptr.child,
        else => @compileError("`data` must be Slice"),
    };
    const ptr: [*]T = @alignCast(@ptrCast(mapped.ptr));
    @memcpy(ptr[0..len], data);
    return @intCast(len * @sizeOf(T));
}

pub fn upload_with_staging(dst: Buffer, staging: Buffer, mapped: []u8, data: anytype) !void {
    const size = copy_to_bytes(mapped, data);
    try copy_buffer(dst, staging, size);
}

pub fn map_mem(mem: v.DeviceMemory, comptime T: type, len: usize) ![]T {
    const device = state.device;
    const size = @sizeOf(T) * len;
    const ptr: [*]T = @alignCast(@ptrCast(try device.mapMemory(mem, 0, size, .{})));
    return ptr[0..len];
}

pub fn unmap_mem(mem: v.DeviceMemory) void {
    state.device.unmapMemory(mem);
}

pub fn init_sync_primitives(device: Device) !void {
    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        state.image_available_semas[i] = try device.createSemaphore(&.{}, null);
        state.render_finished_semas[i] =
            try device.createSemaphore(&.{}, null);
        state.in_flight_fences[i] =
            try device.createFence(&.{ .flags = .{ .signaled = true } }, null);
    }
    state.compute_finished_sema =
        try device.createSemaphore(&.{}, null);
    state.compute_in_flight_fence =
            try device.createFence(&.{ .flags = .{ .signaled = true } }, null);

}

pub fn begin_draw() !void {
    const device = state.device;
    const curr_frame = state.per_frame.curr_frame;
    const cmd = state.graphics_command_buffers[curr_frame];

    state.per_frame.present_image_idx = try acquire_image(curr_frame);
    state.per_frame.cmd = cmd;

    try device.resetCommandBuffer(cmd, .{});
    try device.beginCommandBuffer(cmd, &.{});
}

pub fn end_draw() !void {
    const curr_frame = &state.per_frame.curr_frame;
    const device = state.device;
    const cmd = state.per_frame.cmd;
    defer state.per_frame.cmd = .null_handle;

    try device.endCommandBuffer(cmd);

    try submit_graphics_cmd(state.graphics_command_buffers[curr_frame.*], curr_frame.*, state.per_frame.present_image_idx);
    curr_frame.* = (curr_frame.* + 1) % MAX_FRAMES_IN_FLIGHT;
    state.frame_counter += 1;
    state.per_frame.triangle_texture_ct = curr_frame.* * MAX_TEXTURE;
}

pub fn begin_2d() void {
    const device = state.device;
    const cmd = state.per_frame.cmd;
    const image_idx = state.per_frame.present_image_idx;
    const frame_buffer = state.frame_buffers[image_idx];

    state.per_frame.vert_ct = 0;
    state.per_frame.curr_texture = .null_handle;

    device.cmdBeginRenderPass(cmd, &.{
        .render_pass = state.render_pass, .framebuffer = frame_buffer,
        .render_area = .{
            .offset = .{.x=0,.y=0},
            .extent = state.extent,
        },
        .clear_value_count = 1,
        .p_clear_values = &.{
            .{
                .color = .{ .float_32 = .{0,0,0,1} },
            }
        },
        }, .@"inline");

    device.cmdBindPipeline(cmd, .graphics, state.graphics_pipeline);

    device.cmdSetViewport(cmd, 0, &.{state.viewport});
    device.cmdSetScissor(cmd, 0, &.{state.scissor});
}

pub fn end_2d() void {
    const device = state.device;
    const cmd = state.per_frame.cmd;

    device.cmdEndRenderPass(cmd);
}

pub fn begin_camera(camera: Camera) void {
    state.per_frame.camera = camera;
}

pub fn end_camera() void {
    state.per_frame.camera = .init;
}

pub fn draw_particles_to_off_screen(
    particle_vert_ct: u32
) void {
    // Render particles system to a HDR texture
    const device = state.device;
    const cmd = state.per_frame.cmd;
    const curr_frame = state.per_frame.curr_frame;

    device.cmdBeginRenderPass(cmd, &.{
        .render_pass = state.off_screen_render_pass, .framebuffer = state.hdr_frame_buffer,
        .render_area = .{
            .offset = .{.x=0,.y=0},
            .extent = .{
                .width = state.extent.width,
                .height = state.extent.height,
            },
        },
        .clear_value_count = 1,
        .p_clear_values = &.{
            .{
                .color = .{ .float_32 = .{0,0,0,1} },
            }
        },
    }, .@"inline");
    device.cmdBindPipeline(cmd, .graphics, state.off_screen_graphics_pipeline);
    device.cmdSetViewport(cmd, 0, &.{state.viewport});
    device.cmdSetScissor(cmd, 0, &.{state.scissor});

    device.cmdBindDescriptorSets(cmd,
        .graphics, state.particle_pl_layout, 0, &.{ state.particle_desc_set[curr_frame] }, null);
    device.cmdDraw(cmd, particle_vert_ct, 1, 0, 0);

    device.cmdEndRenderPass(cmd);
}

pub fn acquire_image(curr_frame: u32) !u32 {
    const device = state.device;
    _ = try device.waitForFences(&.{state.in_flight_fences[curr_frame]}, .true, std.math.maxInt(u64));
    try device.resetFences(&.{state.in_flight_fences[curr_frame]});

    const next_result = try device.acquireNextImageKHR(state.swapchain, std.math.maxInt(u64), state.image_available_semas[curr_frame], .null_handle);
    return next_result.image_index;
}

pub fn submit_graphics_cmd(curr_command_buffer: v.CommandBuffer, curr_frame: u32, image_idx: u32) !void {
    const device = state.device;
    const wait_semas: []const v.Semaphore = &.{
        state.compute_finished_sema, // waits on the last computaion
        state.image_available_semas[curr_frame]
    };
    const signal_semas: []const v.Semaphore = &.{
        state.render_finished_semas[curr_frame],
    };
    try device.queueSubmit(state.graphics_queue, &.{.{
        .wait_semaphore_count = @intCast(wait_semas.len),
        .p_wait_semaphores = wait_semas.ptr,
        .p_wait_dst_stage_mask = &.{ .{ .vertex_input = true }, .{ .color_attachment_output = true } },
        .command_buffer_count = 1,
        .p_command_buffers = &.{curr_command_buffer},
        .signal_semaphore_count = @intCast(signal_semas.len),
        .p_signal_semaphores = signal_semas.ptr,
    }}, state.in_flight_fences[curr_frame]);

    _ = try device.queuePresentKHR(state.present_queue, &.{
        .wait_semaphore_count = @intCast(signal_semas.len),
        .p_wait_semaphores = signal_semas.ptr,
        .swapchain_count = 1, .p_swapchains = @ptrCast(&state.swapchain),
        .p_image_indices = @ptrCast(&image_idx),
    });
}

pub fn push_constant(comptime T: type, data: *const T) void {
    state.device.cmdPushConstants(state.per_frame.cmd, state.particle_pl_layout, .{ .vertex = true, .fragment = true, .compute = true }, 0, @sizeOf(T), data);
}

pub fn compute_fence() !void {
    _ = try state.device.waitForFences(&.{state.compute_in_flight_fence}, .true, std.math.maxInt(u64));
    try state.device.resetFences(&.{state.compute_in_flight_fence});
}

pub fn begin_dispatch() ![]const f32 {
    const device = state.device;
    const cmd = state.compute_command_buffer;

    const query_ct = state.per_frame.query_ct;
    if (query_ct > 0) {
        var timestamps: [MAX_QUERY]u64 = undefined;
        _ = try device.getQueryPoolResults(state.query_pool, 0, query_ct,
            @sizeOf(u64)*query_ct, &timestamps, @sizeOf(u64),
            .{ .@"64" = true, .wait = true });
        for (0..query_ct/2) |i| {
            const ns = @as(f32, @floatFromInt(timestamps[i*2+1] - timestamps[i*2])) * state.physical_device_props.limits.timestamp_period;
            state.per_frame.durations[i] = ns / std.time.ns_per_s;
            // std.log.info("compute shader [{}] time = {d:.4} ms", .{i, ns / std.time.ns_per_ms});
        }
    }
    state.per_frame.cmd = cmd;
    state.per_frame.query_ct = 0;
    try device.resetCommandBuffer(cmd, .{});
    try device.beginCommandBuffer(cmd, &.{});
    device.cmdResetQueryPool(cmd, state.query_pool, 0, MAX_QUERY);

    return state.per_frame.durations[0..query_ct/2];
}

pub fn use_compute(compute_stage: u32) void {
    const device = state.device;
    const cmd = state.per_frame.cmd;

    device.cmdBindPipeline(cmd, .compute, state.compute_pipelines[compute_stage]);
    device.cmdBindDescriptorSets(cmd, .compute, state.particle_pl_layout, 0, &.{state.particle_desc_set[state.per_frame.curr_frame]}, null);
}

pub fn sync_buf(buf: Buffer) void {
    const device = state.device;
    const cmd = state.per_frame.cmd;
    const barrier = v.BufferMemoryBarrier{
        .src_access_mask = .{ .transfer_write = true, .shader_write = true },
        .dst_access_mask = .{ .shader_read = true, .shader_write = true },
        .src_queue_family_index = v.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = v.QUEUE_FAMILY_IGNORED,
        .buffer = buf.buf,
        .offset = 0,
        .size = v.WHOLE_SIZE,
    };
    device.cmdPipelineBarrier(
        cmd,
        .{ .transfer = true, .compute_shader = true },             // src stage
        .{ .compute_shader = true },       // dst stage
        .{},                               // dependency flags
        null,                              // memory barriers
        &.{barrier},                       // buffer memory barriers
        null,                              // image memory barriers
    );
}

pub fn clear_buf(buf: Buffer) void {
    const device = state.device;
    const cmd = state.per_frame.cmd;
    device.cmdFillBuffer(cmd, buf.buf, 0, v.WHOLE_SIZE, 0);
    sync_buf(buf);
}

pub fn dispatch_compute(dispatch_x: u32) void {
    const device = state.device;
    const cmd = state.per_frame.cmd;

    device.cmdWriteTimestamp(cmd, .{ .compute_shader = true }, state.query_pool, state.per_frame.query_ct);
    state.per_frame.query_ct += 1;
    device.cmdDispatch(cmd, dispatch_x, 1, 1);
    device.cmdWriteTimestamp(cmd, .{ .compute_shader = true }, state.query_pool, state.per_frame.query_ct);
    state.per_frame.query_ct += 1;

}

pub fn end_dispatch() !void {
    const device = state.device;
    const cmd = state.per_frame.cmd;
    defer state.per_frame.cmd = .null_handle;
        
    //device.cmdWriteTimestamp(cmd, .{ .bottom_of_pipe = true }, state.query_pool, state.per_frame.query_ct);
    //state.per_frame.query_ct += 1;
    try device.endCommandBuffer(cmd);

    const submit_info = v.SubmitInfo {
        .command_buffer_count = 1,
        .p_command_buffers = &.{cmd},
        .signal_semaphore_count = 1,
        .p_signal_semaphores = &.{state.compute_finished_sema},
    };
    try device.queueSubmit(state.graphics_queue, &.{submit_info}, state.compute_in_flight_fence);
}

pub const Rect = struct {
    pos: [2]f32, // topleft
    size: [2]f32,

    pub fn screen() Rect {
        return .{
            .pos = .{-state.aspect_ratio,-1},
            .size = .{2*state.aspect_ratio,2},
        };
    }

    pub fn from_center(pos: [2]f32, size: [2]f32) Rect {
        return .{
            .pos = @as(V2, pos) - @as(V2, size)/m.splat2(2),
            .size = size,
        };
    }

    pub fn point_in(rect: Rect, p: [2]f32) bool {
        return  rect.pos[0] <= p[0] and rect.pos[0]+rect.size[0] >= p[0]
            and rect.pos[1] <= p[1] and rect.pos[1]+rect.size[1] >= p[1];

    }

};

pub const Color = [4]f32;
const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

pub const Triangle_Constant = extern struct {
    pure_color: u32,
    aspect_ratio: f32,
    camera: Camera,
};

pub const Camera = extern struct {
    pos: [2]f32 = .{0,0},
    zoom: f32 = 1,

    pub const init = Camera { .pos = .{0,0}, .zoom = 1 };

    pub fn translate(self: Camera, pos: V2) V2 {
        return (pos - self.pos) * m.splat2(self.zoom);
    }

    pub fn untranslate(self: Camera, pos: V2) V2 {
        return pos / m.splat2(self.zoom) + self.pos;
    }
};

pub fn from_pixel(p: f32) f32 {
    return p / @as(f32, @floatFromInt(state.extent.width * 2));
}

pub const Draw = struct {
    fn push_vertex(vertex: Vertex_Data) void {
        state.per_frame.vertexes.append(state.gpa, vertex) catch @panic("OOM");
    }
    
    fn push_rect_vertex(rect: Rect, color: [4]f32, tex_coord: [4][2]f32) void {
        push_vertex(.{ .pos = rect.pos,                      .tex = tex_coord[0], .color = color });
        push_vertex(.{ .pos = rect.pos + V2{rect.size[0],0}, .tex = tex_coord[1], .color = color });
        push_vertex(.{ .pos = rect.pos + V2{0,rect.size[1]}, .tex = tex_coord[2], .color = color });

        push_vertex(.{ .pos = rect.pos + V2{rect.size[0],0}, .tex = tex_coord[1], .color = color });
        push_vertex(.{ .pos = rect.pos + @as(V2, rect.size), .tex = tex_coord[3], .color = color });
        push_vertex(.{ .pos = rect.pos + V2{0,rect.size[1]}, .tex = tex_coord[2], .color = color });
    }

    fn draw_vertex() void {
        const curr_frame = state.per_frame.curr_frame;
        const device = state.device;
        const cmd = state.per_frame.cmd;

        const vert_ct: u32 = @intCast(state.per_frame.vertexes.items.len);
        @memcpy(state.graphics_vert_maps[curr_frame][state.per_frame.vert_ct..state.per_frame.vert_ct+vert_ct], state.per_frame.vertexes.items);
        state.per_frame.vertexes.clearRetainingCapacity();


        device.cmdBindVertexBuffers(cmd, 0, &.{state.graphics_vert_bufs[curr_frame].buf}, &.{0});
        device.cmdDraw(cmd, @intCast(vert_ct), 1, state.per_frame.vert_ct, 0);
        state.per_frame.vert_ct += vert_ct;
    }

    pub fn topleft() [2]f32 {
        return .{
            -state.aspect_ratio,
            -1,
        };
    }

    pub fn botright() [2]f32 {
        return .{
            state.aspect_ratio,
            1,
        };
    }

    pub fn rectangle(rect: Rect, color: Color) void {
        texture(rect, color, null);
    }

    pub fn texture(rect: Rect, color: Color, tex: ?v.ImageView) void {
        texture2(rect, color, tex, .{
            .{0,0},
            .{1,0},
            .{0,1},
            .{1,1},
        });
    }

    // tex_coord order:
    //   topleft (pos),
    //   topright,
    //   botleft,
    //   botright
    pub fn texture2(rect: Rect, color: Color, tex: ?v.ImageView, tex_coord: [4][2]f32) void {
        prepare_texture(tex);
        push_rect_vertex(rect, color, tex_coord);
        draw_vertex();
    }

    fn prepare_texture(tex: ?v.ImageView) void {
        var constant = Triangle_Constant { .pure_color = 0, .camera = state.per_frame.camera, .aspect_ratio = state.aspect_ratio };
        if (tex) |tex_inner| {
            if (tex_inner != state.per_frame.curr_texture) {
                state.per_frame.curr_texture = tex_inner;
                const texture_ct = &state.per_frame.triangle_texture_ct;
                write_texture_to_descriptor(texture_ct.*, tex_inner);
                state.device.cmdBindDescriptorSets(state.per_frame.cmd, .graphics, state.triangle_pl_layout, 0, state.triangle_desc_set[texture_ct.*..][0..1], null);
                texture_ct.* += 1;
            }
        } else {
            constant.pure_color = 1;
        }
        push_constant(Triangle_Constant, &constant);
    }

    // pub fn line(start: V2, end: V2, thick: f32, color: Color) void {
    //     const l = end - start;
    //     const orthoganal_l = m.normalize(.{ l[1], -l[0] });
    //     const pos = start - orthoganal_l * m.splat2(thick/2);
    // }

    pub fn measure_font_h(scale: f32) f32 {
        const font = state.font;
        const pixel_scale = 1.0/@as(f32, @floatFromInt(state.extent.width)) * scale;
        return pixel_scale * font.size/2;
    }

    pub fn measure_text(str: []const u8, scale: f32) [2]f32 {
        const font = state.font;
        const pixel_scale = 1.0/@as(f32, @floatFromInt(state.extent.width)) * scale;
        var local_pos: f32 = 0;
        for (str) |ch| {
            const packed_char = font.packed_chars[ch - font.code_first_char];
            const advance = packed_char.xadvance * pixel_scale;
            local_pos += advance;
        }
        return .{local_pos, measure_font_h(scale)};
    }

    pub fn text(pos: [2]f32, str: []const u8, scale: f32, color: [4]f32) void {
        const font = state.font;
        const pixel_scale = 1.0/@as(f32, @floatFromInt(state.extent.width)) * scale;
        const font_h = pixel_scale * font.size/2;

        prepare_texture(font.bitmap.view);

        var local_pos = pos;
        for (str) |ch| {
            const packed_char = font.packed_chars[ch - font.code_first_char];
            const aligned_quad = font.aligned_quads[ch - font.code_first_char];

            const advance = packed_char.xadvance * pixel_scale;
            const w =
                @as(f32, @floatFromInt(packed_char.x1 - packed_char.x0))
                * pixel_scale;
            const h =
                @as(f32, @floatFromInt(packed_char.y1 - packed_char.y0))
                * pixel_scale;
            const left = local_pos[0] + (packed_char.xoff * pixel_scale);
            const bot = local_pos[1] -
                (packed_char.yoff * pixel_scale) - @as(f32, @floatFromInt(packed_char.y1 - packed_char.y0))
                * pixel_scale;
            _ = bot;
            const top = local_pos[1] + (font_h - h);
            const tex_coord = [4][2]f32 {
                .{ aligned_quad.s0, aligned_quad.t0 },
                .{ aligned_quad.s1, aligned_quad.t0 },
                .{ aligned_quad.s0, aligned_quad.t1 },
                .{ aligned_quad.s1, aligned_quad.t1 },
            };
            push_rect_vertex(.{.pos = .{left, top}, .size = .{w,h}}, color, tex_coord);
            local_pos[0] += advance;
        }
        draw_vertex();
    }
};
