const Vulkan = @This();
vkb: v.BaseWrapper = undefined,
instance_handle : v.Instance = .null_handle,
instance_wrapper: v.InstanceWrapper = undefined,
instance        : Instance = undefined,
surface         : v.SurfaceKHR = .null_handle,
physical_device : v.PhysicalDevice = .null_handle,
graphics_family : u32 = undefined,
present_family  : u32 = undefined,
surface_details : v.SurfaceCapabilitiesKHR = undefined,
format          : v.SurfaceFormatKHR = undefined,
present_mode    : v.PresentModeKHR = undefined,
extent          : v.Extent2D = undefined,
device_handle   : v.Device = .null_handle,
device_wrapper  : v.DeviceWrapper = undefined,
device          : Device = undefined,
graphics_queue  : v.Queue = .null_handle,
present_queue   : v.Queue = .null_handle,
swapchain       : v.SwapchainKHR = .null_handle,
image_views     : []v.ImageView = &.{},
vert            : v.ShaderModule = .null_handle,
frag            : v.ShaderModule = .null_handle,
render_pass     : v.RenderPass = .null_handle,
frame_buffers   : []v.Framebuffer = &.{},
// pub fn init_window(w: u32, h: u32, name: []const u8) void {
//
// }
pub var state = Vulkan {};
const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

pub fn init_instance() !Instance {
    state.vkb = v.BaseWrapper.load(vkGetInstanceProcAddr);
    var app_info = v.ApplicationInfo {
        .application_version = @bitCast(v.API_VERSION_1_0),
        .engine_version = @bitCast(v.API_VERSION_1_0),
        .api_version = @bitCast(v.API_VERSION_1_0),
    };
    app_info.p_application_name = "Hello Triangle";
    app_info.p_engine_name = "No Engine";

    var create_info = v.InstanceCreateInfo {};
    create_info.p_application_info = &app_info;
    create_info.enabled_layer_count = 1;
    const layers: []const [*:0]const u8 = &.{"VK_LAYER_KHRONOS_validation"};
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

    return state.instance;
}

pub fn init_surface(window: *r.RGFW_window) !v.SurfaceKHR {
    // FIXME: #platform
    const create_info = v.Win32SurfaceCreateInfoKHR {
        .hwnd = @ptrCast(r.RGFW_window_getHWND(window)),
        .hinstance = @ptrCast(r.RGFW_window_getHINSTANCE()),
    };
    state.surface = try state.instance.createWin32SurfaceKHR(&create_info, null);
    return state.surface;
}

pub fn init_device(arena: std.mem.Allocator, window_width: u32, window_height: u32) !Device {
    var device_count: u32 = 0;
    _ = try state.instance.enumeratePhysicalDevices(&device_count, null);
    log.info("found {} devices: ", .{device_count});
    if (device_count == 0) @panic("no devic found");
    const devices = try arena.alloc(v.PhysicalDevice, device_count);
    _ = try state.instance.enumeratePhysicalDevices(&device_count, devices.ptr);
    state.physical_device = devices[0];

    var queue_family_count: u32 = 0;
    state.instance.getPhysicalDeviceQueueFamilyProperties(state.physical_device, &queue_family_count, null);
    log.info("found {} queue family", .{queue_family_count});
    const families = try arena.alloc(v.QueueFamilyProperties, queue_family_count);
    state.instance.getPhysicalDeviceQueueFamilyProperties(state.physical_device, &queue_family_count, families.ptr);
    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;
    for (0..queue_family_count) |i| {
        if (families[i].queue_flags.graphics)
            graphics_family = @intCast(i);
        if (try state.instance.getPhysicalDeviceSurfaceSupportKHR(state.physical_device, @intCast(i), state.surface) == .true)
            present_family = @intCast(i);
    }
    if (graphics_family == null) @panic("cannot found graphics family queue");
    if (present_family == null) @panic("cannot found present family queue");
    state.graphics_family = graphics_family.?;
    state.present_family = present_family.?;

    const priority: []const f32 = &.{1};
    const device_queue_create_infos: []const v.DeviceQueueCreateInfo = &.{
        .{
            .queue_family_index = state.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = priority.ptr,
        },
        .{
            .queue_family_index = state.present_family,
            .queue_count = 1,
            .p_queue_priorities = priority.ptr,
        },
    };
    const device_feature = v.PhysicalDeviceFeatures {};
    const extensions: []const [*:0]const u8 = &.{
        v.extensions.khr_swapchain.name,
    };
    const device_create_info = v.DeviceCreateInfo {
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

    state.device_handle = try state.instance.createDevice(state.physical_device, &device_create_info, null);
    state.device_wrapper = v.DeviceWrapper.load(state.device_handle, state.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    state.device = Device.init(state.device_handle, &state.device_wrapper);
    return state.device;
}

pub const Queues = struct {
    graphics_queue: v.Queue,
    present_queue: v.Queue,
};

pub fn init_queues(device: Device) Queues {
    state.graphics_queue = device.getDeviceQueue(state.graphics_family, 0);
    state.present_queue = device.getDeviceQueue(state.present_family, 0);
    return .{
        .graphics_queue = state.graphics_queue,
        .present_queue = state.present_queue,
    };
}

pub fn init_swapchain(device: Device) !v.SwapchainKHR {
    const image_count = state.surface_details.min_image_count + 1;
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
    if (state.graphics_family != state.present_family) {
        create_info.image_sharing_mode = .concurrent;
        create_info.queue_family_index_count = 2;
        create_info.p_queue_family_indices = &.{ state.graphics_family, state.present_family };
    }

    state.swapchain = try device.createSwapchainKHR(&create_info, null);
    return state.swapchain;
}

pub fn init_image_views(arena: std.mem.Allocator, device: Device) ![]v.ImageView {
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
    return state.image_views;
}

pub fn cleanup() void {
    state.instance.destroyInstance(null);
}


const v = @import("vk.zig");
const r = @import("RGFW");

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

pub const ShaderModules = struct {
    vert: v.ShaderModule,
    frag: v.ShaderModule,
};

pub fn init_shader_modules() !ShaderModules {
    state.vert = try create_shader_module(@alignCast(@embedFile("shader.spv")));
    state.frag = try create_shader_module(@alignCast(@embedFile("shader.spv")));
    return .{ .vert = state.vert, .frag = state.frag };
}

pub fn init_render_pass(device: Device) !v.RenderPass {
    const color_attachment = v.AttachmentDescription {
        .format = state.format.format,
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

    state.render_pass = try device.createRenderPass(&render_pass_info, null);
    return state.render_pass;
}

pub fn init_frame_buffers(arena: std.mem.Allocator, device: Device) ![]v.Framebuffer {
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
    return state.frame_buffers;
}
