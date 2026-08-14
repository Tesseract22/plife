const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const v = @import("thirdparty/vk.zig");
const vulkan = @import("vulkan.zig");
const Texture = vulkan.Texture;

const c = @import("c");

var font_id: u8 = 0;
const Font = @This();
content: []const u8,
id: u8,

pub fn load_font_content(io: Io, file_path: []const u8, gpa: Allocator) !Font {
    var ttf_f = try Io.Dir.cwd().openFile(io, file_path, .{});
    var buf: [256]u8 = undefined;
    var file_reader = ttf_f.reader(io, &buf);
    const ttf_content = file_reader.interface.allocRemaining(gpa, .unlimited) catch @panic("OOM");
    defer font_id += 1; return .{ .content = ttf_content, .id = font_id };
}

pub const Static = struct {
    bitmap: Texture,
    packed_chars: []c.stbtt_packedchar,
    aligned_quads: []c.stbtt_aligned_quad,
    code_first_char: u21,
    code_char_num: u32,
    size: f32,

    pub fn init_from_file(
        ttf_file_path: []const u8,
        code_first_char: u21, code_char_num: u32,
        atlas_size: [2]u32,
        font_size: f32,
        a: std.mem.Allocator,) !Static {

        const ttf_f = try std.fs.cwd().openFile(ttf_file_path, .{});
        const ttf_content = try ttf_f.readToEndAlloc(a, 1024*1024*1024);
        defer a.free(ttf_content);

        return init(ttf_content, code_first_char, code_char_num, atlas_size, font_size, a);
    }

    pub fn init(
        ttf_content: []const u8,
        code_first_char: u21, code_char_num: u32,
        atlas_size: [2]u32,
        font_size: f32,
        a: std.mem.Allocator,) !Static {

        const font_ct = c.stbtt_GetNumberOfFonts(ttf_content.ptr);
        std.log.info("font count: {}", .{ font_ct });
        if (font_ct <= 0) unreachable;

        const font_bitmap = try a.alloc(u8, atlas_size[0] * atlas_size[1]);
        defer a.free(font_bitmap);
        const packed_chars = try a.alloc(c.stbtt_packedchar, code_char_num);
        const aligned_quads = try a.alloc(c.stbtt_aligned_quad, code_char_num);

        var ctx = c.stbtt_pack_context {};

        assert(c.stbtt_PackBegin(
                &ctx,
                font_bitmap.ptr,
                @intCast(atlas_size[0]),
                @intCast(atlas_size[1]),
                0,
                1,
                null,
        ) == 1);

        assert(c.stbtt_PackFontRange(
            &ctx,
            ttf_content.ptr,
            0,
            font_size,
            code_first_char,
            @intCast(code_char_num),
            packed_chars.ptr,
        ) == 1);

        c.stbtt_PackEnd(&ctx);

        //
        // Populate the bitmap
        //
        for (0..code_char_num) |i| {
            var _x: f32 = undefined;
            var _y: f32 = undefined;
            c.stbtt_GetPackedQuad(packed_chars.ptr,
                @intCast(atlas_size[0]), @intCast(atlas_size[1]),
                @intCast(i),
                &_x,
                &_y,
                &aligned_quads[i],
                0);
        }
        const texture = try vulkan.create_texture(
            .r8_unorm,
            atlas_size[0], atlas_size[1],
            .{ .sampled = true, .transfer_dst = true },
            .@"undefined", .{ .r = .one, .g = .one, .b = .one, .a = .r });
        const size = atlas_size[0]*atlas_size[1];
        const staging = try vulkan.create_staging_buffer(size);
        defer staging.destroy();
        const mapped  = try vulkan.map_mem(staging.mem, u8, size);
        defer vulkan.unmap_mem(staging.mem);
        @memcpy(mapped, font_bitmap);

        //
        // Layout Transition
        //
        const device = vulkan.state.device;
        const cmd = try vulkan.begin_tmp_cmd();
        {
            // Transit to transfer_dst
            const barrier = v.ImageMemoryBarrier {
                .old_layout = .undefined,
                .new_layout = .transfer_dst_optimal,
                .src_queue_family_index = v.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = v.QUEUE_FAMILY_IGNORED,
                .image = texture.image,
                .subresource_range = .{
                    .aspect_mask = .{ .color = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .src_access_mask = .{},
                .dst_access_mask = .{ .transfer_write = true }
            };
            device.cmdPipelineBarrier(cmd, .{ .top_of_pipe = true }, .{ .transfer = true }, .{}, null, null, &.{barrier});
        }
        const region = v.BufferImageCopy {
            .buffer_offset = 0,
            .buffer_row_length = 0, .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1
            },
            .image_offset = .{.x=0,.y=0,.z=0},
            .image_extent = .{
                .width = atlas_size[0], .height = atlas_size[1],
                .depth = 1
            }
        };
        device.cmdCopyBufferToImage(cmd, staging.buf, texture.image, .transfer_dst_optimal, &.{region});
        {
            // Transit to transfer_dst
            const barrier = v.ImageMemoryBarrier {
                .old_layout = .transfer_dst_optimal,
                .new_layout = .shader_read_only_optimal,
                .src_queue_family_index = v.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = v.QUEUE_FAMILY_IGNORED,
                .image = texture.image,
                .subresource_range = .{
                    .aspect_mask = .{ .color = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .src_access_mask = .{ .transfer_write = true},
                .dst_access_mask = .{ .shader_read = true }
            };
            device.cmdPipelineBarrier(cmd, .{ .transfer = true }, .{ .fragment_shader = true }, .{}, null, null, &.{barrier});
        }
        try vulkan.end_tmp_cmd(cmd);
        return .{
            .bitmap = texture,
            .packed_chars = packed_chars,
            .aligned_quads = aligned_quads,
            .code_first_char = code_first_char,
            .code_char_num = code_char_num,
            .size = font_size,
        };
    }

    pub fn deinit(static: *Static, gpa: Allocator) void {
        static.bitmap.destroy();
        gpa.free(static.packed_chars);
        gpa.free(static.aligned_quads);
    }

    pub fn get_or_load(static: *Static, code: u21) struct { c.stbtt_packedchar, c.stbtt_aligned_quad } {
        assert(static.code_first_char >= code and static.code_first_char + static.code_char_num < code);
        const idx = code - static.code_first_char;
        return .{
            static.packed_chars.items[idx],
            static.aligned_quads.items[idx],
        };
    }
};
