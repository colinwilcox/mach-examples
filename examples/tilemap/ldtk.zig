const std = @import("std");
const assets = @import("assets");
const mach = @import("mach");
const math = mach.math;

// Bare minimum fields we need to extract from the LDTK JSON for this demo

pub const autoLayerTile = struct {
    px: []u32,
    src: []f32,
    f: u32,
    t: u32,
};

pub const layer_instance = struct {
    levelId: u32,
    intGridCsv: []u32,
    autoLayerTiles: []autoLayerTile,
    __cWid: u32,
    __cHei: u32,
    __gridSize: u32,
};
pub const ldtk_level = struct { identifier: []u8, iid: []u8, worldX: f32, worldY: f32, layerInstances: []layer_instance };

pub const ldtk_data = struct {
    iid: []u8,
    jsonVersion: []u8,
    levels: []ldtk_level,
};

pub fn ParseLDTK(data: []const u8) !std.json.Parsed(ldtk_data) {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const parsed = try std.json.parseFromSlice(ldtk_data, allocator, data, .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true });
    return parsed;
}

// Convert these integer tile coords to float vec2 world coords (flip y axis)
pub fn GetWorldCoords(x: u32, y: u32) math.Vec3 {
    return math.vec3(@floatFromInt(x), @as(f32, @floatFromInt(y)) * -1.0, 0);
}
