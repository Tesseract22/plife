pub fn rgb_from_hsv(hsv: [3]f32) [3]f32 {
    const h, const s, const v = hsv;
    if (s == 0.0) {
        return .{ v, v, v };
    }

    const hh = @mod(h, 360.0) / 60.0;
    const i = @as(u32, @intFromFloat(@floor(hh)));
    const f = hh - @floor(hh);

    const p = v * (1.0 - s);
    const q = v * (1.0 - s * f);
    const t = v * (1.0 - s * (1.0 - f));

    return switch (i % 6) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        5 => .{ v, p, q },
        else => unreachable,
    };
}

pub inline fn dist2(a: V2, b: V2) f32 {
    return len2(a-b);
}

pub inline fn len(a: V2) f32 {
    return @sqrt(len2(a));
}

pub inline fn len2(a: V2) f32 {
    return @reduce(.Add, a*a);
}

pub inline fn normalize(a: V2) V2 {
    return a / splat2(len(a));
}

pub inline fn splat2(a: f32) V2 {
    return @splat(a);
}

pub inline fn splat3(a: f32) V3 {
    return @splat(a);
}

pub inline fn splat4(a: f32) V4 {
    return @splat(a);
}

pub const cast = std.math.lossyCast;

const driver = @import("main.zig");
const std = @import("std");
pub const GRID_CELL_SIDE_COUNT = driver.GRID_CELL_SIDE_COUNT;
pub const GRID_CELL_COUNT      = driver.GRID_CELL_COUNT;
pub const GRID_CELL_SIZE       = driver.GRID_CELL_SIZE;

pub fn cell_from_normalized_pos(pos_normalized: V2) ?@Vector(2, u32) {
    for (@as([2]f32, pos_normalized)) |coord| {
        if (coord < 0 or coord > 1) return null;
    }
    // `pos` could have 1 or -1 as coordinate, which would cause `bin_coord` to be EQUAL to GRID_CELL_SIDE_COUNT, making it out of bound
    const cell_f = pos_normalized / splat2(GRID_CELL_SIZE/2.0);
    return .{
        std.math.clamp(@as(u32, @floor(cell_f[0])), 0, GRID_CELL_SIDE_COUNT-1),
        std.math.clamp(@as(u32, @floor(cell_f[1])), 0, GRID_CELL_SIDE_COUNT-1),
    };

}
pub inline fn cell_from_pos(pos: V2) ?@Vector(2, u32) {
    const pos_normalized = (pos + splat2(1)) / splat2(2); // this is now from 0-1
    return cell_from_normalized_pos(pos_normalized);
}

pub inline fn bin_from_cell(coord: [2]u32) u32 {
    return coord[1] * GRID_CELL_SIDE_COUNT + coord[0];
}

pub inline fn apply_aspect_ratio(pos: [2]f32, ratio: f32) [2]f32 {
    return .{ pos[0]/ratio, pos[1] };
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);
