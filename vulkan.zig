const Vulkan = @This();
vkb: v.BaseWrapper = undefined,
instance_handle : v.Instance = .null_handle,
instance_wrapper: v.InstanceWrapper = undefined,
instance        : Instance = undefined,
surface         : v.SurfaceKHR = .null_handle,
// pub fn init_window(w: u32, h: u32, name: []const u8) void {
// 
// }
pub var state = Vulkan {};
const vkGetInstanceProcAddr = @extern(v.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan-1",
});

pub fn init_instance() Instance {
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
    const handle = state.vkb.createInstance(&create_info, null) catch |e| fatal("cannot create instance: {}", .{e});

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

pub fn create_shader_module(device: Device, src: [] align(4) const u8) !v.ShaderModule {
    const u32_slice = std.mem.bytesAsSlice(u32, src);
    const create_info = v.ShaderModuleCreateInfo {
        .code_size = src.len,
        .p_code = u32_slice.ptr,
    };
    return device.createShaderModule(&create_info, null);
}
