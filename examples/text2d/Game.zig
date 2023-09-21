const std = @import("std");
const zigimg = @import("zigimg");
const assets = @import("assets");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;
const ecs = mach.ecs;
const Text2D = mach.gfx2d.Text2D;
const FTFontManager = @import("FTFontManager.zig");
const math = mach.math;

const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

timer: mach.Timer,
player: mach.ecs.EntityID,
direction: Vec2 = vec2(0, 0),
spawning: bool = false,
spawn_timer: mach.Timer,
fps_timer: mach.Timer,
frame_count: usize,
texts: usize,
rand: std.rand.DefaultPrng,
time: f32,

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

pub const Pipeline = enum(u32) {
    default,
};

var fonts: FTFontManager = undefined;
var font: mach.gfx2d.FontRenderer = undefined;

const upscale = 1.0;

pub fn init(
    engine: *mach.Mod(.engine),
    text2d: *mach.Mod(.engine_text2d),
    game: *mach.Mod(.game),
) !void {
    // The Mach .core is where we set window options, etc.
    core.setTitle("gfx.Text2D example");

    // We can create entities, and set components on them. Note that components live in a module
    // namespace, e.g. the `.engine_text2d` module could have a 3D `.location` component with a different
    // type than the `.physics2d` module's `.location` component if you desire.

    fonts = try FTFontManager.init();
    _ = try fonts.ensureFontFaceBytes(
        engine.allocator,
        // TODO: put these params into a struct for passing identically into .renderer()
        "Roboto Medium",
        0,
        assets.fonts.roboto_medium.bytes,
    );
    font = try fonts.renderer("Roboto Medium", 0);

    const player = try engine.newEntity();
    try text2d.set(player, .pipeline, @intFromEnum(Pipeline.default));
    try text2d.set(player, .transform, Mat4x4.scaleScalar(upscale).mul(&Mat4x4.translate(vec3(0, 0, 0))));
    try text2d.set(player, .text, "Text2D but with spaces 😊 :) :) :)\nand\nnewlines!");
    try text2d.set(player, .font, font);
    try text2d.set(player, .font_size, 48);
    try text2d.set(player, .color, vec4(0.6, 1.0, 0.6, 1.0));

    try text2d.send(.init, .{});
    try text2d.send(.initPipeline, .{Text2D.PipelineOptions{
        .pipeline = @intFromEnum(Pipeline.default),
    }});
    try text2d.send(.updated, .{@intFromEnum(Pipeline.default)});

    game.state = .{
        .timer = try mach.Timer.start(),
        .spawn_timer = try mach.Timer.start(),
        .player = player,
        .fps_timer = try mach.Timer.start(),
        .frame_count = 0,
        .texts = 0,
        .rand = std.rand.DefaultPrng.init(1337),
        .time = 0,
    };
}

pub fn deinit(engine: *mach.Mod(.engine)) !void {
    fonts.deinit(engine.allocator);
}

pub fn tick(
    engine: *mach.Mod(.engine),
    text2d: *mach.Mod(.engine_text2d),
    game: *mach.Mod(.game),
) !void {
    // TODO(engine): event polling should occur in mach.Engine module and get fired as ECS events.
    var iter = core.pollEvents();
    var direction = game.state.direction;
    var spawning = game.state.spawning;
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] -= 1,
                    .right => direction.v[0] += 1,
                    .up => direction.v[1] += 1,
                    .down => direction.v[1] -= 1,
                    .space => spawning = true,
                    else => {},
                }
            },
            .key_release => |ev| {
                switch (ev.key) {
                    .left => direction.v[0] += 1,
                    .right => direction.v[0] -= 1,
                    .up => direction.v[1] -= 1,
                    .down => direction.v[1] += 1,
                    .space => spawning = false,
                    else => {},
                }
            },
            .close => try engine.send(.exit, .{}),
            else => {},
        }
    }
    game.state.direction = direction;
    game.state.spawning = spawning;

    var player_transform = text2d.get(game.state.player, .transform).?;
    var player_pos = player_transform.translation().divScalar(upscale);
    if (spawning and game.state.spawn_timer.read() > 1.0 / 60.0) {
        // Spawn new entities
        _ = game.state.spawn_timer.lap();
        for (0..1) |_| {
            var new_pos = player_pos;
            new_pos.v[0] += game.state.rand.random().floatNorm(f32) * 25;
            new_pos.v[1] += game.state.rand.random().floatNorm(f32) * 25;

            const new_entity = try engine.newEntity();
            try text2d.set(new_entity, .pipeline, @intFromEnum(Pipeline.default));
            try text2d.set(new_entity, .transform, Mat4x4.scaleScalar(upscale).mul(&Mat4x4.translate(new_pos)));
            try text2d.set(new_entity, .text, "!$?");
            try text2d.set(new_entity, .font, font);
            // TODO: if this font size is different, there's a panic
            try text2d.set(new_entity, .font_size, 48);
            try text2d.set(new_entity, .color, vec4(0.6, 1.0, 0.6, 1.0));
            game.state.texts += 1;
        }
    }

    // Multiply by delta_time to ensure that movement is the same speed regardless of the frame rate.
    const delta_time = game.state.timer.lap();

    // Rotate entities
    var archetypes_iter = engine.entities.query(.{ .all = &.{
        .{ .engine_text2d = &.{.transform} },
    } });
    while (archetypes_iter.next()) |archetype| {
        var ids = archetype.slice(.entity, .id);
        var transforms = archetype.slice(.engine_text2d, .transform);
        for (ids, transforms) |id, *old_transform| {
            _ = id;
            var location = old_transform.*.translation();
            // var transform = old_transform.mul(&Mat4x4.translate(-location));
            // transform = mat.rotateZ(0.3 * delta_time).mul(&transform);
            // transform = transform.mul(&Mat4x4.translate(location));
            var transform = Mat4x4.ident;
            transform = transform.mul(&Mat4x4.translate(location));
            transform = transform.mul(&Mat4x4.rotateZ(2 * math.pi * game.state.time));
            transform = transform.mul(&Mat4x4.scaleScalar(@min(math.cos(game.state.time / 2.0), 0.5)));

            // TODO: .set() API is substantially slower due to internals
            // try text2d.set(id, .transform, transform);
            old_transform.* = transform;
        }
    }

    // Calculate the player position, by moving in the direction the player wants to go
    // by the speed amount.
    const speed = 200.0 / upscale;
    player_pos.v[0] += direction.x() * speed * delta_time;
    player_pos.v[1] += direction.y() * speed * delta_time;
    try text2d.set(game.state.player, .transform, Mat4x4.scaleScalar(upscale).mul(&Mat4x4.translate(player_pos)));
    try text2d.send(.updated, .{@intFromEnum(Pipeline.default)});

    // Perform pre-render work
    try text2d.send(.preRender, .{@intFromEnum(Pipeline.default)});

    // Render a frame
    try engine.send(.beginPass, .{gpu.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }});
    try text2d.send(.render, .{@intFromEnum(Pipeline.default)});
    try engine.send(.endPass, .{});
    try engine.send(.present, .{}); // Present the frame

    // Every second, update the window title with the FPS
    if (game.state.fps_timer.read() >= 1.0) {
        try core.printTitle("gfx.Text2D example [ FPS: {d} ] [ Texts: {d} ]", .{ game.state.frame_count, game.state.texts });
        game.state.fps_timer.reset();
        game.state.frame_count = 0;
    }
    game.state.frame_count += 1;
    game.state.time += delta_time;
}
