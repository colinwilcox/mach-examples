const std = @import("std");
const zigimg = @import("zigimg");
const assets = @import("assets");
const mach = @import("mach");
const ldtk = @import("ldtk.zig");

const App = @import("main.zig").App;

const core = mach.core;
const gpu = mach.gpu;
const ecs = mach.ecs;
const Sprite = mach.gfx.Sprite;
const math = mach.math;

const vec2 = math.vec2;
const vec3 = math.vec3;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

const root_path = "assets/";
const world_path = root_path ++ "world/";
const sprites_path = root_path ++ "sprites/";
pub const example_tilemap_path = root_path ++ "monochrome_tilemap_packed.png";
pub const example_tilemap = @embedFile(example_tilemap_path);

pub const example_map_path = root_path ++ "platformer.ldtk";
pub const example_map = @embedFile(example_map_path);

timer: mach.Timer,
player: mach.ecs.EntityID,
direction: Vec2 = vec2(0, 0),
spawning: bool = false,
spawn_timer: mach.Timer,
fps_timer: mach.Timer,
frame_count: usize,
sprites: usize,
rand: std.rand.DefaultPrng,
time: f32,
jumping: bool,
jump_strength: f32,
y_velocity: f32,

const d0 = 0.000001;

// Each module must have a globally unique name declared, it is impossible to use two modules with
// the same name in a program. To avoid name conflicts, we follow naming conventions:
//
// 1. `.mach` and the `.mach_foobar` namespace is reserved for Mach itself and the modules it
//    provides.
// 2. Single-word names like `.game` are reserved for the application itself.
// 3. Libraries which provide modules MUST be prefixed with an "owner" name, e.g. `.ziglibs_imgui`
//    instead of `.imgui`. We encourage using e.g. your GitHub name, as these must be globally
//    unique.
//
pub const name = .game;
pub const Mod = mach.Mod(@This());

pub var map_data: ldtk.ldtk_data = undefined;

pub var screen_scale: Vec3 = undefined;
pub var scale_transform: Mat4x4 = undefined;

pub const Pipeline = enum(u32) {
    default,
};

pub const components = struct {
    pub const map_tile = void;
    pub const character = void;
};

pub const Box = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub fn init(
    engine: *mach.Engine.Mod,
    sprite_mod: *Sprite.Mod,
    game: *Mod,
) !void {
    // The Mach .core is where we set window options, etc.
    core.setTitle("gfx.Tilemap example");
    core.setSize(.{ .width = 384, .height = 256 });

    const parsed = try ldtk.ParseLDTK(&example_map.*);
    map_data = parsed.value;
    // try std.json.stringify(map_data, .{ .whitespace = .indent_tab }, std.io.getStdOut().writer());

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, e.g. the `.mach_gfx_sprite` module could have a 3D `.location` component with a different
    // type than the `.physics2d` module's `.location` component if you desire.
    screen_scale = vec3(1, 1, 1);
    scale_transform = Mat4x4.scale(screen_scale);

    const player = try engine.newEntity();
    try sprite_mod.set(player, .transform, Mat4x4.translate(vec3(-0.02, 0, 0)));
    try sprite_mod.set(player, .size, vec2(16, 16));
    try sprite_mod.set(player, .uv_transform, Mat3x3.translate(vec2(0, 192)));
    try sprite_mod.set(player, .pipeline, @intFromEnum(Pipeline.default));

    try sprite_mod.send(.init, .{});
    try sprite_mod.send(.initPipeline, .{Sprite.PipelineOptions{
        .pipeline = @intFromEnum(Pipeline.default),
        .texture = try loadTexture(engine),
    }});
    try sprite_mod.send(.updated, .{@intFromEnum(Pipeline.default)});

    game.state = .{
        .timer = try mach.Timer.start(),
        .spawn_timer = try mach.Timer.start(),
        .player = player,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .sprites = 0,
        .rand = std.rand.DefaultPrng.init(1337),
        .time = 0,
        .jumping = false,
        .jump_strength = 150,
        .y_velocity = 0,
    };

    // Create sprites for each tile in tilemape
    const currentLevel = map_data.levels[0];
    const offset = vec3(-200, 100, 0);
    for (currentLevel.layerInstances) |layer| {
        // try std.json.stringify(layer, .{ .whitespace = .indent_tab }, std.io.getStdOut().writer());
        for (layer.autoLayerTiles) |tile_data| {
            const new_entity = try engine.newEntity();
            const new_pos = ldtk.GetWorldCoords(tile_data.px[0], tile_data.px[1]);
            const offset_pos = Vec3.add(&new_pos, &offset);
            const t_pos = Vec3.mul(&offset_pos, &screen_scale);
            const tr = Mat4x4.translate(t_pos);
            const t = Mat4x4.mul(&tr, &scale_transform);
            // try game.set(new_entity, .map_tile, {});
            try sprite_mod.set(new_entity, .transform, t);
            try sprite_mod.set(new_entity, .size, vec2(16, 16));
            try sprite_mod.set(new_entity, .uv_transform, Mat3x3.translate(vec2(tile_data.src[0], tile_data.src[1])));
            try sprite_mod.set(new_entity, .pipeline, @intFromEnum(Pipeline.default));
            game.state.sprites += 1;
        }
    }
}

pub fn tick(
    engine: *mach.Engine.Mod,
    sprite_mod: *Sprite.Mod,
    game: *Mod,
) !void {
    // TODO(engine): event polling should occur in mach.Engine module and get fired as ECS events.
    var iter = core.pollEvents();
    var direction = game.state.direction;
    // var spawning = game.state.spawning;
    var jumping = game.state.jumping;

    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] -= 1,
                    .right => direction.v[0] += 1,
                    .up => direction.v[1] += 1,
                    .down => direction.v[1] -= 1,
                    .space => {
                        jumping = true;
                        game.state.y_velocity += game.state.jump_strength;
                    },
                    else => {},
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] += 1,
                    .right => direction.v[0] -= 1,
                    .up => clearLevel(engine, sprite_mod, game),
                    .down => direction.v[1] += 1,
                    // .space => jumping = false,
                    else => {},
                }
            },
            .close => try engine.send(.exit, .{}),
            else => {},
        }
    }
    game.state.direction = direction;
    // game.state.spawning = spawning;
    game.state.jumping = jumping;

    var player_transform = sprite_mod.get(game.state.player, .transform).?;
    var player_size = sprite_mod.get(game.state.player, .size).?;
    var player_pos = player_transform.translation();
    const player_center = vec3(player_pos.x() + player_size.x() / 2, player_pos.y() + player_size.y() / 2, 0);

    const player_bb = Box{ .h = 16, .w = 16, .x = player_pos.x(), .y = player_pos.y() };
    _ = player_bb;

    // Multiply by delta_time to ensure that movement is the same speed regardless of the frame rate.
    const delta_time = game.state.timer.lap();

    var archetypes_iter = engine.entities.query(.{ .all = &.{
        .{ .mach_gfx_sprite = &.{.transform} },
    } });

    // Collision checks, set up bounding boxes
    // We'll use this one for each tile sprite
    var tile_bb = Box{ .h = 16, .w = 16, .x = 0, .y = 0 };
    // We'll use this one to check each direction from player
    const v_down = vec3(0, -8, 0);
    const v_up = vec3(0, 8, 0);
    const v_left = vec3(-8, 0, 0);
    const v_right = vec3(8, 0, 0);

    var on_floor = false;
    var wall_left = false;
    var wall_right = false;
    var wall_up = false;

    while (archetypes_iter.next()) |archetype| {
        const ids = archetype.slice(.entity, .id);
        const transforms = archetype.slice(.mach_gfx_sprite, .transform);
        for (ids, transforms) |id, *old_transform| {
            // don't check against ourselves
            if (game.state.player == id) continue;

            const location = old_transform.*.translation();
            tile_bb.x = location.v[0];
            tile_bb.y = location.v[1];
            if (!on_floor) {
                on_floor = PointInsideBox(tile_bb, Vec3.add(&player_center, &v_down));
            }
            if (!wall_left) {
                wall_left = PointInsideBox(tile_bb, Vec3.add(&player_center, &v_left));
            }
            if (!wall_right) {
                wall_right = PointInsideBox(tile_bb, Vec3.add(&player_center, &v_right));
            }
            if (!wall_up) {
                wall_up = PointInsideBox(tile_bb, Vec3.add(&player_center, &v_up));
            }
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount.
    const speed = 150.0;
    const gravity = 240.0;
    game.state.y_velocity -= gravity * delta_time;

    if ((direction.x() > 0 and !wall_right) or (direction.x() < 0 and !wall_left)) {
        player_pos.v[0] += direction.x() * speed * delta_time;
    }

    if (wall_up and game.state.y_velocity > 0) {
        game.state.y_velocity = 0;
    }
    if (on_floor and game.state.y_velocity < 0) {
        game.state.y_velocity = 0;
        jumping = false;
    }

    player_pos.v[1] += game.state.y_velocity * delta_time;

    try sprite_mod.set(game.state.player, .transform, Mat4x4.translate(player_pos));
    try sprite_mod.send(.updated, .{@intFromEnum(Pipeline.default)});

    // Perform pre-render work
    try sprite_mod.send(.preRender, .{@intFromEnum(Pipeline.default)});

    // Render a frame
    try engine.send(.beginPass, .{gpu.Color{ .r = 0, .g = 0, .b = 0, .a = 1.0 }});
    try sprite_mod.send(.render, .{@intFromEnum(Pipeline.default)});
    try engine.send(.endPass, .{});
    try engine.send(.present, .{}); // Present the frame

    // Every second, update the window title with the FPS
    if (game.state.fps_timer.read() >= 1.0) {
        try core.printTitle("gfx.Sprite example [ FPS: {d} ] [ Sprites: {d} ]", .{ game.state.frame_count, game.state.sprites });
        game.state.fps_timer.reset();
        game.state.frame_count = 0;
    }
    game.state.frame_count += 1;
    game.state.time += delta_time;
}

// clear all but player, doesn't work
fn clearLevel(engine: *mach.Engine.Mod, sprite_mod: *Sprite.Mod, game: *Mod) void {
    _ = sprite_mod;
    var archetypes_iter = engine.entities.query(.{ .all = &.{
        .{ .mach_gfx_sprite = &.{.transform} },
    } });
    while (archetypes_iter.next()) |archetype| {
        const ids = archetype.slice(.entity, .id);
        for (ids) |id| {
            if (game.state.player == id) continue;
            // try engine.removeEntity(id); // no work
        }
    }
}

// TODO: move this helper into gfx module
fn loadTexture(
    engine: *mach.Engine.Mod,
) !*gpu.Texture {
    const device = engine.state.device;
    const queue = device.getQueue();

    // Load the image from memory
    var img = try zigimg.Image.fromMemory(engine.allocator, example_tilemap);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };

    // Create a GPU texture
    const texture = device.createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(img.width * 4)),
        .rows_per_image = @as(u32, @intCast(img.height)),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(engine.allocator, pixels);
            defer data.deinit(engine.allocator);
            queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }
    return texture;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}

//2d bounds check
fn PointInsideBox(b1: Box, p1: Vec3) bool {
    return (p1.x() > b1.x and p1.x() < b1.x + b1.w and p1.y() > b1.y and p1.y() < b1.y + b1.h);
}

fn AABBCheck(b1: Box, b2: Box) bool {
    return !(b1.x + b1.w < b2.x or b1.x > b2.x + b2.w or b1.y + b1.h < b2.y or b1.y > b2.y + b2.h);
}
