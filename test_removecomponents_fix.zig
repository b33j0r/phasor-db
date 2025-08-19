const std = @import("std");
const Database = @import("src/Database.zig");
const testing = std.testing;

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

test "removeComponents with type-only tuples" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entity with components
    const entity_id = try db.createEntity(.{
        Position{ .x = 1.0, .y = 2.0 },
        Velocity{ .dx = 0.5, .dy = 0.5 },
    });

    // Verify both components exist
    const entity = db.getEntity(entity_id).?;
    try testing.expect(entity.has(Position));
    try testing.expect(entity.has(Velocity));

    // Remove component using TYPE-ONLY tuple (the fix)
    try db.removeComponents(entity_id, .{Velocity});

    // Verify Velocity was removed but Position remains
    const updated_entity = db.getEntity(entity_id).?;
    try testing.expect(updated_entity.has(Position));
    try testing.expect(!updated_entity.has(Velocity));

    std.debug.print("SUCCESS: removeComponents now works with type-only tuples!\n", .{});
}