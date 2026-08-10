const Configuration = @This();
specie_ct: u32,
particle_force_configs: [MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE]Force_Config = undefined,
collision_force_config: Force_Config,
species: [MAX_PARTICLE_SPECIE]Particle_Specie,

pub fn serialize(config: Configuration, io: std.Io, path: []const u8) !void {
    var f = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true }) catch @panic("OOM");
    defer f.close(io);

    var buf: [256]u8 = undefined;
    var f_writer = f.writer(io, &buf);
    const writer = &f_writer.interface;
    try config.print(writer);
}

pub fn print(config: Configuration, writer: *std.Io.Writer) !void {
    const s_info = @typeInfo(Configuration).@"struct";
    inline for (s_info.field_names, s_info.field_types) |name, ty| {
        const val = @field(config, name);
        switch (ty) {
            u32 => {
                try writer.print("{s}={}\n", .{name, val});
            },
            [MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE]Force_Config
             => {
                for (0..config.specie_ct) |i| {
                    for (0..config.specie_ct) |j| {
                        const force = val[i*config.specie_ct + j];
                        try writer.print("{s} {} {}={f},{f}\n", .{
                            name, i, j,
                            Hex_Float{.f=force.strength}, Hex_Float{.f=force.radius}
                        });
                    }
                }
            },
            Force_Config => {
                try writer.print("{s}={f},{f}\n", .{
                    name,
                    Hex_Float{.f=val.strength}, Hex_Float{.f=val.radius}
                });
            },
            [MAX_PARTICLE_SPECIE]Particle_Specie => {
                for (0..config.specie_ct) |i| {
                    try writer.print("{s} {}={f},{f},{f}\n", .{
                        name,
                        i,
                        Hex_Float{.f=val[i].color[0]},
                        Hex_Float{.f=val[i].color[1]},
                        Hex_Float{.f=val[i].color[2]},
                    });
                }
            },
            else => @compileError("Unsupported Configuration type"),
        }
    }
    try writer.flush();
}

pub fn deserialize(io: std.Io, path: []const u8) !Configuration {
    var f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);

    var buf: [256]u8 = undefined;
    var f_reader = f.reader(io, &buf);
    const reader = &f_reader.interface;
    return parse(reader);
}

pub fn parse(reader: *std.Io.Reader) !Configuration {
    const use_hex = true;
    var res: Configuration = undefined;
    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) {
            continue;
        }
        const s_info = @typeInfo(Configuration).@"struct";
        const name, const idx1, const idx2, const rhs = blk: {
            var it = std.mem.splitScalar(u8, line, '=');
            const lhs = it.next() orelse return error.MissingLhs;
            const rhs = it.next() orelse return error.MissingRhs;

            it = std.mem.splitScalar(u8, lhs, ' ');
            const name = it.next().?;
            const idx1 = it.next();
            const idx2 = it.next();
            break :blk .{name, idx1, idx2, rhs};
        };
        inline for (s_info.field_names, s_info.field_types) |f_name, ty| {
            if (std.mem.eql(u8, f_name, name)) {
                switch (ty) {
                    u32 => {
                        @field(res, f_name) = try std.fmt.parseInt(u32, rhs, 10);
                    },
                    [MAX_PARTICLE_SPECIE*MAX_PARTICLE_SPECIE]Force_Config => {
                        if (idx1 == null or idx2 == null) return error.MissingIndex;
                        const i = try std.fmt.parseInt(u32, idx1.?, 10);
                        const j = try std.fmt.parseInt(u32, idx2.?, 10);
                        @field(res, f_name)[i * res.specie_ct + j] = try parse_force_config(rhs, use_hex); // TODO: use a more sensible speice
                    },
                    Force_Config => {
                        @field(res, f_name) = try parse_force_config(rhs, use_hex);
                    },
                    [MAX_PARTICLE_SPECIE]Particle_Specie => {
                        if (idx1 == null) return error.MissingIndex;
                        const i = try std.fmt.parseInt(u32, idx1.?, 10);
                        var it = std.mem.splitScalar(u8, rhs, ',');
                        const r = try Hex_Float.parse(it.next() orelse return error.MissingField, use_hex);
                        const g = try Hex_Float.parse(it.next() orelse return error.MissingField, use_hex);
                        const b = try Hex_Float.parse(it.next() orelse return error.MissingField, use_hex);
                        @field(res, f_name)[i] = .{ .color = .{r,g,b} };
                    },
                    else => @compileError("Unsupported Configuration type"),
                }
                break;
            }
        } else return error.UnrecognizedField;
    }
    return res;
}

pub const Hex_Float = struct {
    f: f32,

    pub fn format(self: Hex_Float, writer: *std.Io.Writer) !void {
        try writer.print("{d:.6} {x}", .{self.f, @as(u32, @bitCast(self.f))});
    }

    pub fn parse(str: []const u8, use_hex: bool) !f32 {
        var it = std.mem.splitScalar(u8, str, ' ');
        const f_str = it.next() orelse return error.MissingField;
        const hex_str = it.next() orelse return error.MissingField;
        if (use_hex) {
            const hex = try std.fmt.parseInt(u32, hex_str, 16);
            return @bitCast(hex);
        } else {
            const f = try std.fmt.parseFloat(f32, f_str);
            return f;
        }
    }
};

pub fn parse_force_config(str: []const u8, use_hex: bool) !Force_Config {
    var it = std.mem.splitScalar(u8, str, ',');
    const strength = it.next() orelse return error.MissingField;
    const radius = it.next() orelse return error.MissingField;
    return .{ .strength = try Hex_Float.parse(strength, use_hex), .radius = try Hex_Float.parse(radius, use_hex) };
}

const std = @import("std");
const log = std.log;
const main = @import("main.zig");

const MAX_PARTICLE_SPECIE = main.MAX_PARTICLE_SPECIE;
const Force_Config = main.Force_Config;
const Particle_Specie = main.Particle_Specie;

test Configuration {
    const a = std.testing.allocator;
    const config1 = Configuration {
        .specie_ct = 1,
        .particle_force_configs = undefined,
        .collision_force_config = undefined,
        .species                = undefined,
    };
    var allocating = std.Io.Writer.Allocating.init(a);
    const writer = &allocating.writer;
    try config1.print(writer);

    const str = try allocating.toOwnedSlice();
    defer a.free(str);
    var reader = std.Io.Reader.fixed(str);
    const config2 = try Configuration.parse(&reader);

    try std.testing.expectEqual(config1.specie_ct, config2.specie_ct);
    for (0..config1.specie_ct) |i| {
        for (0..config1.specie_ct) |j| {
            const f1 = config1.particle_force_configs[i * config1.specie_ct + j];
            const f2 = config2.particle_force_configs[i * config1.specie_ct + j];
            try std.testing.expectEqual(f1, f2);
        }
    }
    try std.testing.expectEqual(config1.collision_force_config, config2.collision_force_config);
}
