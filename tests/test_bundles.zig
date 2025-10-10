test "Bundle Entity.getAlloc works with arbitrary structs" {
    const allocator = std.testing.allocator;
    var db = phasor_db.Database.init(allocator);
    defer db.deinit();

    const entity_id = try db.createEntity(.{
        Position{ .x = 1.0, .y = 2.0 },
        Velocity{ .dx = 0.5, .dy = 0.5 },
    });
    const entity = db.getEntity(entity_id) orelse {
        return error.EntityNotFound;
    };
    const owned_movable = entity.getAlloc(allocator, Movable) orelse {
        return error.BundleNotFound;
    };
    defer owned_movable.deinit();
    const movable = owned_movable.ptr;

    try std.testing.expect(movable.pos.x == 1.0);
    try std.testing.expect(movable.pos.y == 2.0);
    try std.testing.expect(movable.vel.dx == 0.5);
    try std.testing.expect(movable.vel.dy == 0.5);
}

test "Bundle Entity.getAlloc fails if any component is missing" {
    const allocator = std.testing.allocator;
    var db = phasor_db.Database.init(allocator);
    defer db.deinit();

    const entity_id = try db.createEntity(.{
        Position{ .x = 1.0, .y = 2.0 },
        // Note: Velocity component is omitted
    });
    const entity = db.getEntity(entity_id) orelse {
        return error.EntityNotFound;
    };
    const owned_movable = entity.getAlloc(allocator, Movable);
    try std.testing.expect(owned_movable == null);
}

// -------
// Imports
// -------

const std = @import("std");

const phasor_db = @import("phasor-db");

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Velocity = fixtures.Velocity;
const Movable = fixtures.Moveable;
