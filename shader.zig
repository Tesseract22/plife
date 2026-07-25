const Vertex = struct {
    const positions = [3]V2 {
        .{0.0, -0.5}, 
        .{0.5, 0.5},
        .{-0.5, 0.5}
    };
    const colors = [3]V3 {
        .{1.0, 0.0, 0.0},
        .{0.0, 1.0, 0.0},
        .{0.0, 0.0, 1.0},
    };

    const frag_color = @extern(*addrspace(.output) V3, .{
        .name = "frag_color",
        .decoration = .{ .location = 0 },
    });

    fn main() callconv(.spirv_vertex) void {
        const i = spirv.vertex_index ;
        const pos = positions[i];
        spirv.position_out.* = .{
            pos[0], pos[1], 0, 1
        };
        frag_color.* = colors[i];
    }
};

const Fragment = struct {
    const frag_color = @extern(*addrspace(.input) V3, .{
        .name = "frag_color",
        .decoration = .{ .location = 0 },
    });
    const out_color = @extern(*addrspace(.output) V4, .{
        .name = "out_color",
        .decoration = .{ .location = 0 },
    });


    fn main() callconv(.{ .spirv_fragment = .{ .depth_assumption = .greater } }) void {
        out_color.* = .{
            frag_color[0],
            frag_color[1],
            frag_color[2],
            1,
        };
    }
};

comptime {
    @export(&Vertex.main,   .{ .name = "vert" });
    @export(&Fragment.main, .{ .name = "frag" });
}

const V2 = @Vector(2, f32);
const V3 = @Vector(3, f32);
const V4 = @Vector(4, f32);

const std = @import("std");
const spirv = std.spirv;
