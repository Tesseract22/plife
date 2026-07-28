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
