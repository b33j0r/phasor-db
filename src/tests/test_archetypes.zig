const std = @import("std");
const testing = std.testing;

const root = @import("../root.zig");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const Archetype = root.Archetype;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Health = fixtures.Health;
const Marker = fixtures.Marker;
const LargeComponent = fixtures.LargeComponent;

test "Archetype create empty" {
    const allocator = std.testing.allocator;
    var archetype = try Archetype.fromComponents(allocator, .{
        Position{
            .x = 0.0,
            .y = 0.0,
        },
        Health{
            .max = 100,
            .current = 50,
        },
    });
    defer archetype.deinit(allocator);

    try testing.expectEqual(2, archetype.columns.len);
    try testing.expectEqual(componentId(Position), archetype.columns[0].id);
    try testing.expectEqual(componentId(Health), archetype.columns[1].id);
    try testing.expectEqual(0, archetype.entity_ids.items.len);
}

test "Archetype addEntity" {

}