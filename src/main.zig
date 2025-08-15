const std = @import("std");
const ecs = @import("phasor-ecs");

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

pub fn main() !void{
    const allocator = std.heap.c_allocator;
    var db = ecs.Database.init(allocator);
    defer db.deinit();

    const entity = db.createEntity(.{
        Position{ .x = 0.0, .y = 0.0 },
        Velocity{ .x = 1.0, .y = 1.0 },
    });

    const readEntity = db.getEntity(entity).?;
    const position = readEntity.get(Position).?;
    const velocity = readEntity.get(Velocity).?;

    std.debug.print("Entity Position: ({}, {})\n", .{position.x, position.y});
    std.debug.print("Entity Velocity: ({}, {})\n", .{velocity.x, velocity.y});
}