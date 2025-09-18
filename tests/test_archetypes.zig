const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;
const Database = root.Database;

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

test "Archetype transition memory leak - component add/remove cycles" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const num_entities = 50;
    const num_transitions = 20;

    // Create entities with basic components
    var entities = std.ArrayListUnmanaged(u64).empty;
    defer entities.deinit(allocator);

    for (0..num_entities) |i| {
        const entity_id = try db.createEntity(.{Position{ .x = @floatFromInt(i), .y = 0.0 }});
        try entities.append(allocator, entity_id);
    }

    // Perform many archetype transitions
    for (0..num_transitions) |_| {
        // Add Health component to all entities (Position -> Position+Health archetype)
        for (entities.items) |entity_id| {
            try db.addComponents(entity_id, .{Health{ .current = 100, .max = 100 }});
        }

        // Add Velocity component (Position+Health -> Position+Health+Velocity archetype)
        for (entities.items) |entity_id| {
            try db.addComponents(entity_id, .{Velocity{ .dx = 1.0, .dy = 0.0 }});
        }

        // Remove Velocity (Position+Health+Velocity -> Position+Health archetype)
        for (entities.items) |entity_id| {
            try db.removeComponents(entity_id, .{Velocity});
        }

        // Remove Health (Position+Health -> Position archetype)
        for (entities.items) |entity_id| {
            try db.removeComponents(entity_id, .{Health});
        }
    }

    // At the end, all entities should be back in the original Position-only archetype
    for (entities.items) |entity_id| {
        const entity = db.getEntity(entity_id).?;
        try testing.expect(entity.has(Position));
        try testing.expect(!entity.has(Health));
        try testing.expect(!entity.has(Velocity));
    }

    // Clean up
    for (entities.items) |entity_id| {
        try db.removeEntity(entity_id);
    }
}
