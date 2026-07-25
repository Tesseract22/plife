# Vulkan Refactor Notes

## Scope

- Move all Vulkan-related code out of `main.zig` into `vulkan.zig`.
- Keep RGFW-related window creation, event polling, and shutdown in `main.zig`.
- `vulkan.zig` may import/use RGFW only where Vulkan needs it, such as Win32 surface creation or window-size queries.

## API and State

- Preserve the existing public names where possible.
- Make all Vulkan APIs public for now.
- Put most Vulkan objects and handles in the global `vulkan.state`; multi-device support is not needed.
- Use snake_case names for new and extracted code.
- Name the allocator parameter `arena`.
- CPU allocations made through `arena` must not be freed individually.
- During incremental extraction, initialization functions return the Vulkan object(s) they create so the surrounding code can remain structurally similar. For example, replace `const device = blk: { ... };` with `const device = try init_device(...);` while also storing required state globally. Apply this to every initializer where it makes sense; keep `init`, `draw_frame`, `record_command_buffer`, `submit_command_buffer`, and `cleanup` as lifecycle functions that return `void`.

```zig
pub fn init(
    arena: std.mem.Allocator,
    window: *r.RGFW_window,
    window_width: u32,
    window_height: u32,
) !void

pub fn init_instance() !Instance
pub fn init_surface(window: *r.RGFW_window) !v.SurfaceKHR
pub fn init_device(
    arena: std.mem.Allocator,
    window_width: u32,
    window_height: u32,
) !Device
pub fn init_queues(device: Device) Queues

pub fn init_swapchain(device: Device) !v.SwapchainKHR
pub fn init_image_views(arena: std.mem.Allocator, device: Device) ![]v.ImageView

pub fn create_shader_module(src: []align(4) const u8) !v.ShaderModule
pub fn init_shader_modules() !ShaderModules
pub fn init_render_pass(device: Device) !v.RenderPass
pub fn init_graphics_pipeline(device: Device) !v.Pipeline
pub fn init_frame_buffers(arena: std.mem.Allocator, device: Device) ![]v.Framebuffer

pub fn init_command_pool(device: Device) !v.CommandPool
pub fn init_command_buffers(device: Device) !CommandBuffers
pub fn init_sync_primitives(device: Device) !SyncPrimitives

pub fn draw_frame() !void
pub fn record_command_buffer(image_idx: u32) !void
pub fn submit_command_buffer(image_idx: u32) !void

pub fn cleanup() void
```

`Queues`, `ShaderModules`, `CommandBuffers`, and `SyncPrimitives` are public structs or aliases that group the multiple values their initializer creates.

## Errors and Cleanup

- Forward Vulkan errors with `try`.
- Do not add `errdefer` cleanup for partial initialization failures.
- Consolidate the currently distributed Vulkan cleanup into `vulkan.cleanup()`.

## Extraction Granularity

- The user will provide later instructions for the exact extraction grouping; do not choose grouping heuristics yet.
- Merge device-wrapper initialization into `init_device`; do not create `init_device_wrapper`.
- Do not modify tests or build files. If doing so appears necessary, stop and ask the user because the refactor is incorrect.
