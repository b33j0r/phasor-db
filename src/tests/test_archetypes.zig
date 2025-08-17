const std = @import("std");
const testing = std.testing;

const root = @import("../root.zig");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const Archetype = root.Archetype;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Velocity = fixtures.Velocity;
const Health = fixtures.Health;
const Marker = fixtures.Marker;
const LargeComponent = fixtures.LargeComponent;
const TestPositions = fixtures.TestPositions;
const TestHealth = fixtures.TestHealth;
const TestVelocity = fixtures.TestVelocity;
const TestEntity = fixtures.TestEntity;
const archetypeFromComponents = fixtures.archetypeFromComponents;

test "Archetype create empty" {
    const allocator = std.testing.allocator;
    var archetype = try archetypeFromComponents(allocator, .{
        TestPositions.origin,
        TestHealth.damaged,
    });
    defer archetype.deinit();

    const position_index = archetype.getColumnIndexByType(Position).?;
    const health_index = archetype.getColumnIndexByType(Health).?;

    try testing.expectEqual(2, archetype.columns.len);
    try testing.expectEqual(componentId(Position), archetype.columns[position_index].meta.id);
    try testing.expectEqual(componentId(Health), archetype.columns[health_index].meta.id);
    try testing.expectEqual(0, archetype.entity_ids.items.len);
}

test "Archetype calculateId" {
    const allocator = std.testing.allocator;
    const archetype_id = Archetype.calculateId(.{
        TestPositions.origin,
        TestHealth.damaged,
    });

    var archetype = try archetypeFromComponents(allocator, .{
        TestPositions.origin,
        TestHealth.damaged,
    });
    defer archetype.deinit();

    try testing.expectEqual(archetype_id, archetype.id);
}

test "Archetype create with different order of components is the same" {
    const allocator = std.testing.allocator;
    var archetype1 = try archetypeFromComponents(allocator, .{
        TestPositions.origin,
        TestHealth.damaged,
    });
    defer archetype1.deinit();

    var archetype2 = try archetypeFromComponents(allocator, .{
        TestHealth.damaged,
        TestPositions.origin,
    });
    defer archetype2.deinit();

    try testing.expectEqual(archetype1.id, archetype2.id);
}

test "Archetype addEntity" {
    const allocator = std.testing.allocator;
    var archetype = try archetypeFromComponents(allocator, .{
        TestPositions.origin,
        TestHealth.damaged,
    });
    defer archetype.deinit();

    const entity_index = try archetype.addEntity(10, .{
        TestPositions.basic,
        TestHealth.high_max,
    });

    const position_index = archetype.getColumnIndexByType(Position).?;
    const health_index = archetype.getColumnIndexByType(Health).?;

    try testing.expectEqual(1, archetype.entity_ids.items.len);
    try testing.expectEqual(10, archetype.entity_ids.items[entity_index]);
    try testing.expectEqual(1, archetype.columns[position_index].len);
    try testing.expectEqual(1, archetype.columns[health_index].len);

    const position = archetype.columns[position_index].get(entity_index, Position).?;
    const health = archetype.columns[health_index].get(entity_index, Health).?;

    try testing.expectEqual(TestPositions.basic.x, position.x);
    try testing.expectEqual(TestPositions.basic.y, position.y);
    try testing.expectEqual(TestHealth.high_max.max, health.max);
    try testing.expectEqual(TestHealth.high_max.current, health.current);
}

test "Archetype removeEntityByIndex" {
    const allocator = std.testing.allocator;
    var archetype = try archetypeFromComponents(allocator, .{
        TestPositions.origin,
        TestHealth.damaged,
    });
    defer archetype.deinit();

    _ = try archetype.addEntity(10, .{
        TestPositions.basic,
        TestHealth.high_max,
    });

    _ = try archetype.addEntity(20, .{
        TestPositions.alternative,
        TestHealth.very_high,
    });

    const removed_entity_id = try archetype.removeEntityByIndex(0);
    try testing.expectEqual(10, removed_entity_id);

    try testing.expectEqual(1, archetype.entity_ids.items.len);
    try testing.expectEqual(20, archetype.entity_ids.items[0]);
}
