const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const Archetype = root.Archetype;
const Database = root.Database;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Health = fixtures.Health;
const Marker = fixtures.Marker;
const LargeComponent = fixtures.LargeComponent;
const Velocity = fixtures.Velocity;
const TestPositions = fixtures.TestPositions;
const TestHealth = fixtures.TestHealth;
const TestVelocity = fixtures.TestVelocity;
const TestEntity = fixtures.TestEntity;

test "Database init" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try testing.expectEqual(0, db.next_entity_id);
    try testing.expectEqual(0, db.archetypes.count());
    try testing.expectEqual(0, db.entities.count());
}

test "Database addComponents - add to existing entity" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Add Health component
    try db.addComponents(entity_id, .{ .health = TestHealth.full });

    // Entity should now be in a different archetype
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;
    try testing.expectEqual(@as(usize, 2), archetype.columns.len);

    // Should have two archetypes now (original empty one should be pruned)
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Verify entity has both components
    try testing.expectEqual(TestPositions.basic.x, entity.get(Position).?.x);
    try testing.expectEqual(TestHealth.full.current, entity.get(Health).?.current);
}

test "Database addComponents - update existing component" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    const original_archetype_count = db.archetypes.count();

    // Add Position again with different values - should update the existing component
    try db.addComponents(entity_id, .{ .position = TestPositions.alternative });

    // Should still have the same number of archetypes
    try testing.expectEqual(original_archetype_count, db.archetypes.count());

    // Entity should now have the updated position values
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(TestPositions.alternative.x, entity.get(Position).?.x);
    try testing.expectEqual(TestPositions.alternative.y, entity.get(Position).?.y);
}

test "Database addComponents - mixed update existing and add new" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position only
    const entity_id = try db.createEntity(TestEntity.basic_positioned);

    // Add Position with different values AND Velocity (mixed case)
    try db.addComponents(entity_id, .{
        .position = TestPositions.alternative, // Should UPDATE existing Position
        .velocity = TestVelocity.moving_right, // Should ADD new Velocity
    });

    // Entity should now be in a different archetype with both components
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;
    try testing.expectEqual(@as(usize, 2), archetype.columns.len);

    // Verify Position was updated
    try testing.expectEqual(TestPositions.alternative.x, entity.get(Position).?.x);
    try testing.expectEqual(TestPositions.alternative.y, entity.get(Position).?.y);

    // Verify Velocity was added
    try testing.expectEqual(TestVelocity.moving_right.dx, entity.get(Velocity).?.dx);
    try testing.expectEqual(TestVelocity.moving_right.dy, entity.get(Velocity).?.dy);
}

test "Entity has component functionality" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different component combinations
    const multi_component_id = try db.createEntity(TestEntity.healthy_positioned);
    const single_component_id = try db.createEntity(TestEntity.basic_positioned);

    const multi_entity = db.getEntity(multi_component_id).?;
    const single_entity = db.getEntity(single_component_id).?;

    // Entity with multiple components should have all its components
    try testing.expect(multi_entity.has(Position));
    try testing.expect(multi_entity.has(Health));
    try testing.expect(!multi_entity.has(Velocity));

    // Entity with single component should only have that component
    try testing.expect(single_entity.has(Position));
    try testing.expect(!single_entity.has(Health));
    try testing.expect(!single_entity.has(Velocity));
}

test "Entity set component functionality" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);
    var entity = db.getEntity(entity_id).?;

    // Test successful setting of existing components
    try entity.set(TestPositions.alternative);
    try entity.set(TestHealth.damaged);

    const updated_position = entity.get(Position).?;
    const updated_health = entity.get(Health).?;
    try testing.expectEqual(TestPositions.alternative.x, updated_position.x);
    try testing.expectEqual(TestHealth.damaged.current, updated_health.current);

    // Test error when trying to set non-existent component
    const result = entity.set(TestVelocity.moving_right);
    try testing.expectError(error.ComponentNotFound, result);
}

test "Database removeEntity" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Remove the entity
    try db.removeEntity(entity_id);

    // Entity should no longer exist
    try testing.expectEqual(null, db.getEntity(entity_id));

    // Archetype count should be 0 after removing the only entity
    try testing.expectEqual(@as(usize, 0), db.archetypes.count());
}

test "Database removeEntity - non-existent entity" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Try to remove non-existent entity
    const result = db.removeEntity(999);
    try testing.expectError(error.EntityNotFound, result);
}

test "Database removeEntity - multiple entities same archetype" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create multiple entities with same archetype
    const entity1_id = try db.createEntity(TestEntity.healthy_positioned);
    const entity2_id = try db.createEntity(TestEntity.healthy_positioned);
    const entity3_id = try db.createEntity(TestEntity.healthy_positioned);

    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Remove middle entity
    try db.removeEntity(entity2_id);

    // Other entities should still exist
    try testing.expect(db.getEntity(entity1_id) != null);
    try testing.expect(db.getEntity(entity3_id) != null);
    try testing.expectEqual(null, db.getEntity(entity2_id));

    // Archetype should still exist with remaining entities
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Remove all remaining entities
    try db.removeEntity(entity1_id);
    try db.removeEntity(entity3_id);

    // All entities should be gone
    try testing.expectEqual(null, db.getEntity(entity1_id));
    try testing.expectEqual(null, db.getEntity(entity3_id));

    // Archetype should be pruned when empty
    try testing.expectEqual(@as(usize, 0), db.archetypes.count());
}

test "Database removeEntity - different archetypes" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different archetypes
    const basic_entity = try db.createEntity(TestEntity.basic_positioned);
    const healthy_entity = try db.createEntity(TestEntity.healthy_positioned);
    const moving_entity = try db.createEntity(TestEntity.moving_entity);

    try testing.expectEqual(@as(usize, 3), db.archetypes.count());

    // Remove entity from middle archetype
    try db.removeEntity(healthy_entity);

    // Other entities should still exist
    try testing.expect(db.getEntity(basic_entity) != null);
    try testing.expect(db.getEntity(moving_entity) != null);
    try testing.expectEqual(null, db.getEntity(healthy_entity));

    // Only the empty archetype should be pruned
    try testing.expectEqual(@as(usize, 2), db.archetypes.count());

    // Verify remaining entities still have their components
    const basic_ref = db.getEntity(basic_entity).?;
    const moving_ref = db.getEntity(moving_entity).?;

    try testing.expectEqual(TestPositions.basic.x, basic_ref.get(Position).?.x);
    try testing.expectEqual(@as(?*Health, null), basic_ref.get(Health));

    try testing.expectEqual(TestPositions.basic.x, moving_ref.get(Position).?.x);
    try testing.expectEqual(TestVelocity.moving_right.dx, moving_ref.get(Velocity).?.dx);
}

test "Database removeEntity - archetype cleanup edge case" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create single entity and remove it
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 10.0, .y = 20.0 } });
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    try db.removeEntity(entity_id);

    // Database should be completely clean
    try testing.expectEqual(@as(usize, 0), db.archetypes.count());
    try testing.expectEqual(null, db.getEntity(entity_id));

    // Should be able to create new entities normally after cleanup
    const new_entity = try db.createEntity(.{ .position = Position{ .x = 5.0, .y = 15.0 } });
    try testing.expect(db.getEntity(new_entity) != null);
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());
}

test "Database removeEntity - memory safety with complex components" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with large components to test memory management
    const entity1 = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 }, .large_component = LargeComponent{ .data = [_]u8{1} ** 1024, .id = 123 } });

    const entity2 = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 }, .large_component = LargeComponent{ .data = [_]u8{2} ** 1024, .id = 456 } });

    // Verify entities exist and have correct data
    const entity1_ref = db.getEntity(entity1).?;
    const entity2_ref = db.getEntity(entity2).?;

    try testing.expectEqual(@as(u64, 123), entity1_ref.get(LargeComponent).?.id);
    try testing.expectEqual(@as(u64, 456), entity2_ref.get(LargeComponent).?.id);

    // Remove first entity
    try db.removeEntity(entity1);

    // Second entity should still have correct data (no memory corruption)
    const entity2_after = db.getEntity(entity2).?;
    try testing.expectEqual(@as(u64, 456), entity2_after.get(LargeComponent).?.id);
    try testing.expectEqual(@as(u8, 2), entity2_after.get(LargeComponent).?.data[0]);

    // Remove second entity - should clean up archetype
    try db.removeEntity(entity2);
    try testing.expectEqual(@as(usize, 0), db.archetypes.count());
}

test "Database removeComponents - remove from entity" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);

    // Remove Health component
    try db.removeComponents(entity_id, .{ .health = TestHealth.critical });

    // Entity should now be in a different archetype with only Position
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;
    try testing.expectEqual(@as(usize, 1), archetype.columns.len);

    // Should still have Position component
    try testing.expectEqual(TestPositions.basic.x, entity.get(Position).?.x);

    // Should not have Health component
    try testing.expectEqual(@as(?*Health, null), entity.get(Health));
}

test "Database removeComponents - remove non-existent component (no-op)" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with only Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    const original_archetype_count = db.archetypes.count();

    // Try to remove Health (which doesn't exist) - should be a no-op
    try db.removeComponents(entity_id, .{TestHealth.critical});

    // Should still have the same number of archetypes
    try testing.expectEqual(original_archetype_count, db.archetypes.count());

    // Entity should still have original position
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(TestPositions.basic.x, entity.get(Position).?.x);
}

test "Database removeComponents - cannot remove all components" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with only Position
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });

    // Try to remove all components - should fail
    const result = db.removeComponents(entity_id, .{ .position = Position{ .x = 0.0, .y = 0.0 } });
    try testing.expectError(error.CannotRemoveAllComponents, result);
}

test "Database archetype pruning - empty archetype gets cleaned up" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create two entities with same archetype
    const entity1 = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    const entity2 = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 } });

    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Add Health to both entities (they move to new archetype)
    try db.addComponents(entity1, .{ .health = Health{ .current = 100, .max = 100 } });
    try db.addComponents(entity2, .{ .health = Health{ .current = 80, .max = 100 } });

    // Original archetype should be pruned, only new one should remain
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());

    // Verify both entities are in the new archetype and have both components
    const entity1_ref = db.getEntity(entity1).?;
    const entity2_ref = db.getEntity(entity2).?;

    try testing.expectEqual(entity1_ref.archetype_id, entity2_ref.archetype_id);
    try testing.expectEqual(@as(f32, 1.0), entity1_ref.get(Position).?.x);
    try testing.expectEqual(@as(i32, 100), entity1_ref.get(Health).?.current);
    try testing.expectEqual(@as(f32, 3.0), entity2_ref.get(Position).?.x);
    try testing.expectEqual(@as(i32, 80), entity2_ref.get(Health).?.current);
}

test "Database complex component operations" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entity with Position
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });

    // Add multiple components
    try db.addComponents(entity_id, .{ .health = Health{ .current = 100, .max = 100 }, .velocity = Velocity{ .dx = 0.5, .dy = -0.5 } });

    // Verify entity has all three components
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 1.0), entity.get(Position).?.x);
    try testing.expectEqual(@as(i32, 100), entity.get(Health).?.current);
    try testing.expectEqual(@as(f32, 0.5), entity.get(Velocity).?.dx);

    // Remove one component
    try db.removeComponents(entity_id, .{ .velocity = Velocity{ .dx = 0.0, .dy = 0.0 } });

    // Verify entity has remaining components
    const updated_entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 1.0), updated_entity.get(Position).?.x);
    try testing.expectEqual(@as(i32, 100), updated_entity.get(Health).?.current);
    try testing.expectEqual(@as(?*Velocity, null), updated_entity.get(Velocity));
}

// Regression tests for bookkeeping integrity

test "Database component ID consistency" {
    // Regression test: Verify componentId() remains stable across operations
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const id_before = componentId(Position);
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    const id_after = componentId(Position);

    // Component IDs must remain consistent
    try testing.expectEqual(id_before, id_after);

    // Archetype should contain the same component ID
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;

    var found_id = false;
    for (archetype.columns) |column| {
        if (column.meta.id == id_before) {
            found_id = true;
            break;
        }
    }
    try testing.expect(found_id);
}

test "Database entity row_index tracking" {
    // Regression test: Verify entity row_index is correctly tracked
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create multiple entities in same archetype
    const entity1_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    const entity2_id = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 } });

    const entity1 = db.getEntity(entity1_id).?;
    const entity2 = db.getEntity(entity2_id).?;

    // Verify correct row indices
    try testing.expectEqual(@as(usize, 0), entity1.row_index);
    try testing.expectEqual(@as(usize, 1), entity2.row_index);

    // Both should be in same archetype
    try testing.expectEqual(entity1.archetype_id, entity2.archetype_id);
}

test "Database entity get chain integrity" {
    // Regression test: Verify Entity.get() chain works step by step
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    const entity = db.getEntity(entity_id).?;

    // Step 1: Database should contain the archetype
    const archetype = db.archetypes.get(entity.archetype_id);
    try testing.expect(archetype != null);

    // Step 2: Archetype should have the column
    const pos_id = componentId(Position);
    const column = archetype.?.getColumn(pos_id);
    try testing.expect(column != null);

    // Step 3: Column should contain the data
    const pos_ptr = column.?.get(entity.row_index, Position);
    try testing.expect(pos_ptr != null);

    // Step 4: Entity.get() should work end-to-end
    const retrieved_pos = entity.get(Position);
    try testing.expect(retrieved_pos != null);
    try testing.expectEqual(@as(f32, 1.0), retrieved_pos.?.x);
    try testing.expectEqual(@as(f32, 2.0), retrieved_pos.?.y);
}

test "Database query one component" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create multiple entities with Position
    const entity1_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    const entity2_id = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 } });

    // QuerySpec for entities with Position
    var positions = try db.query(.{Position});
    defer positions.deinit();
    try testing.expectEqual(2, positions.count());
    var iter = positions.iterator();
    while (iter.next()) |entity| {
        const pos = entity.get(Position).?;
        if (entity.id == entity1_id) {
            try testing.expectEqual(@as(f32, 1.0), pos.x);
            try testing.expectEqual(@as(f32, 2.0), pos.y);
        } else if (entity.id == entity2_id) {
            try testing.expectEqual(@as(f32, 3.0), pos.x);
            try testing.expectEqual(@as(f32, 4.0), pos.y);
        } else {
            try testing.expect(false);
        }
    }
}

test "Database query multiple components" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different component combinations
    const entity1_id = try db.createEntity(.{ Position{ .x = 1.0, .y = 2.0 }, Health{ .current = 100, .max = 100 } });
    const _entity2_id = try db.createEntity(.{Position{ .x = 3.0, .y = 4.0 }}); // Only position
    const _entity3_id = try db.createEntity(.{Health{ .current = 50, .max = 100 }}); // Only health
    const entity4_id = try db.createEntity(.{ Position{ .x = 5.0, .y = 6.0 }, Health{ .current = 75, .max = 100 } });

    _ = _entity2_id; // Intentionally unused - testing that query doesn't return it
    _ = _entity3_id; // Intentionally unused - testing that query doesn't return it

    // QuerySpec for entities with both Position and Health
    var query_result = try db.query(.{ Position, Health });
    defer query_result.deinit();

    // Should find only entities 1 and 4
    try testing.expectEqual(2, query_result.count());

    var iter = query_result.iterator();
    var found_entity1 = false;
    var found_entity4 = false;

    while (iter.next()) |entity| {
        const pos = entity.get(Position).?;
        const health = entity.get(Health).?;

        if (entity.id == entity1_id) {
            found_entity1 = true;
            try testing.expectEqual(@as(f32, 1.0), pos.x);
            try testing.expectEqual(@as(f32, 2.0), pos.y);
            try testing.expectEqual(@as(i32, 100), health.current);
        } else if (entity.id == entity4_id) {
            found_entity4 = true;
            try testing.expectEqual(@as(f32, 5.0), pos.x);
            try testing.expectEqual(@as(f32, 6.0), pos.y);
            try testing.expectEqual(@as(i32, 75), health.current);
        } else {
            try testing.expect(false); // Should not find entity2 or entity3
        }
    }

    try testing.expect(found_entity1);
    try testing.expect(found_entity4);
}

test "Database createEntity with runtime values - basic case" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // This should fail with current implementation (comptime requirement)
    const runtime_x: f32 = 15.5; // Not comptime-known
    const runtime_y: f32 = 25.7;

    // This line should fail to compile with current code
    const entity_id = try db.createEntity(.{
        Position{ .x = runtime_x, .y = runtime_y },
    });

    // If it works, verify the entity was created correctly
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 15.5), entity.get(Position).?.x);
    try testing.expectEqual(@as(f32, 25.7), entity.get(Position).?.y);
}

test "Database createEntity with function call values" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Helper function to simulate runtime computation
    const computePosition = struct {
        fn call(seed: u32) Position {
            return Position{
                .x = @as(f32, @floatFromInt(seed)) * 1.5,
                .y = @as(f32, @floatFromInt(seed)) * 2.0,
            };
        }
    }.call;

    // This should fail with current implementation
    const entity_id = try db.createEntity(.{
        computePosition(42), // Function call result - not comptime
    });

    // Verify if it works
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 63.0), entity.get(Position).?.x);
    try testing.expectEqual(@as(f32, 84.0), entity.get(Position).?.y);
}

test "Database createEntity same types different values should share archetype" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const x1: f32 = 10.0;
    const y1: f32 = 20.0;
    const x2: f32 = 30.0;
    const y2: f32 = 40.0;

    // Create two entities with same component types but different runtime values
    const entity1_id = try db.createEntity(.{
        Position{ .x = x1, .y = y1 },
    });

    const entity2_id = try db.createEntity(.{
        Position{ .x = x2, .y = y2 },
    });

    // Both entities should exist
    const entity1 = db.getEntity(entity1_id).?;
    const entity2 = db.getEntity(entity2_id).?;

    // They should be in the same archetype (same component types)
    try testing.expectEqual(entity1.archetype_id, entity2.archetype_id);

    // But have different component values
    try testing.expectEqual(@as(f32, 10.0), entity1.get(Position).?.x);
    try testing.expectEqual(@as(f32, 30.0), entity2.get(Position).?.x);

    // Should only have one archetype total
    try testing.expectEqual(@as(usize, 1), db.archetypes.count());
}

test "Database addComponents with runtime values" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();

    // Create an entity with Position
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });

    // Add Health component with runtime values
    const health_current: i32 = random.intRangeAtMost(i32, 10, 100);
    const health_max: i32 = health_current + 10;

    try db.addComponents(entity_id, .{
        Health{ .current = health_current, .max = health_max },
    });

    // Verify entity has both components
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 1.0), entity.get(Position).?.x);
    try testing.expectEqual(health_current, entity.get(Health).?.current);
    try testing.expectEqual(health_max, entity.get(Health).?.max);
}

// Test components for memory stress testing
const GameState = struct {
    score: u32,
    level: u8,
    time_remaining: f32,
};

const PlayerStats = struct {
    experience: u64,
    gold: u32,
    inventory: [16]u32, // Larger struct to stress memory allocation
};

test "Database memory leak - entity lifecycle stress test" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const num_cycles = 100;
    const entities_per_cycle = 50;

    for (0..num_cycles) |cycle| {
        var entities = std.ArrayListUnmanaged(u64).empty;
        defer entities.deinit(allocator);

        // Create many entities with different component combinations
        for (0..entities_per_cycle) |i| {
            const entity_id = if (i % 3 == 0)
                try db.createEntity(.{ .position = Position{ .x = @floatFromInt(i), .y = @floatFromInt(cycle) }, .health = Health{ .current = 100, .max = 100 } })
            else if (i % 3 == 1)
                try db.createEntity(.{ .position = Position{ .x = @floatFromInt(i), .y = @floatFromInt(cycle) }, .velocity = Velocity{ .dx = 1.0, .dy = 0.0 }, .health = Health{ .current = 50, .max = 100 } })
            else
                try db.createEntity(.{ .position = Position{ .x = @floatFromInt(i), .y = @floatFromInt(cycle) } });

            try entities.append(allocator, entity_id);
        }

        // Remove all entities to test cleanup
        for (entities.items) |entity_id| {
            try db.removeEntity(entity_id);
        }

        // After cleanup, there should be no archetypes or entities remaining
        // If memory is leaking, archetypes might persist even when empty
        try testing.expectEqual(@as(usize, 0), db.entities.count());
    }
}

test "Database simulated ECS renderer" {
    // This test simulates a renderer. It is meant to make sure the
    // database can handle a real-world ECS use case that is more
    // complex than simple component queries.

    // The goal is to efficiently group and sort by: (Viewport, Layer)
    // This is a two-level iteration that should map to our archetype
    // design neatly (if a little fragmented for small numbers of
    // entities).
    const Types = struct {
        pub const Camera = struct {};
        pub fn Viewport(V: i32) type {
            const Self = struct {
                pub const __group_key__: i32 = V;
                pub const __trait__ = ViewportN;
            };
            return Self;
        }
        pub const ViewportN = struct {};

        pub fn Layer(L: i32) type {
            const Self = struct {
                pub const __group_key__: i32 = L;
                pub const __trait__ = LayerN;
            };
            return Self;
        }
        pub const LayerN = struct {};

        pub const Renderable = struct {};
    };

    const Camera = Types.Camera;
    const Viewport = Types.Viewport;
    const ViewportN = Types.ViewportN;
    const Layer = Types.Layer;
    const LayerN = Types.LayerN;
    const Renderable = Types.Renderable;

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // The example has two viewports, each with two layers.

    const camera_a = try db.createEntity(.{
        Camera{},
        Viewport(0){},
    });
    const renderable_a1 = try db.createEntity(.{
        Renderable{},
        Viewport(0){},
        Layer(0){},
    });
    const renderable_a2 = try db.createEntity(.{
        Renderable{},
        Viewport(0){},
        Layer(1){},
    });

    const camera_b = try db.createEntity(.{
        Camera{},
        Viewport(1){},
    });
    const renderable_b1 = try db.createEntity(.{
        Renderable{},
        Viewport(1){},
        Layer(0){},
    });
    const renderable_b2 = try db.createEntity(.{
        Renderable{},
        Viewport(1){},
        Layer(1){},
    });

    var viewport_groups = try db.groupBy(ViewportN);
    defer viewport_groups.deinit();

    try testing.expectEqual(2, viewport_groups.count());

    var viewport_groups_it = viewport_groups.iterator();

    // Collect Viewport A
    const viewport_group_a = viewport_groups_it.next().?;
    var viewport_camera_a_query = try viewport_group_a.query(.{Camera});
    defer viewport_camera_a_query.deinit();

    // Collect Renderables in Viewport A
    var layer_groups_a = try viewport_group_a.groupBy(LayerN);
    defer layer_groups_a.deinit();

    // Get the two layer groups in Viewport A
    var layer_groups_a_it = layer_groups_a.iterator();
    const layer_renderable_g1 = layer_groups_a_it.next().?;
    const layer_renderable_g2 = layer_groups_a_it.next().?;

    // Verify we have two layer groups with our renderables
    var layer_renderable_g1_it = layer_renderable_g1.iterator();
    const layer_renderable_a1 = layer_renderable_g1_it.next().?;
    try testing.expectEqual(renderable_a1, layer_renderable_a1.id);
    try testing.expectEqual(null, layer_renderable_g1_it.next()); // null

    var layer_renderable_g2_it = layer_renderable_g2.iterator();
    const layer_renderable_a2 = layer_renderable_g2_it.next().?;
    try testing.expectEqual(renderable_a2, layer_renderable_a2.id);
    try testing.expectEqual(null, layer_renderable_g2_it.next()); // null

    // Collect Viewport B
    const viewport_group_b = viewport_groups_it.next().?;
    var viewport_camera_b_query = try viewport_group_b.query(.{Camera});
    defer viewport_camera_b_query.deinit();

    // Collect Renderables in Viewport B
    var layer_groups_b = try viewport_group_b.groupBy(LayerN);
    defer layer_groups_b.deinit();

    // Get the two layer groups in Viewport B
    var layer_groups_b_it = layer_groups_b.iterator();
    const layer_renderable_b1 = layer_groups_b_it.next().?;
    const layer_renderable_b2 = layer_groups_b_it.next().?;

    // Verify we have two layer groups with our renderables
    var layer_renderable_b1_it = layer_renderable_b1.iterator();
    const layer_renderable_b1_entity = layer_renderable_b1_it.next().?;
    try testing.expectEqual(renderable_b1, layer_renderable_b1_entity.id);
    try testing.expectEqual(null, layer_renderable_b1_it.next()); // null

    var layer_renderable_b2_it = layer_renderable_b2.iterator();
    const layer_renderable_b2_entity = layer_renderable_b2_it.next().?;
    try testing.expectEqual(renderable_b2, layer_renderable_b2_entity.id);
    try testing.expectEqual(null, layer_renderable_b2_it.next()); // null

    // Test subqueries last
    const viewport_camera_a = viewport_camera_a_query.first().?.id;
    try testing.expectEqual(camera_a, viewport_camera_a);

    const viewport_camera_b = viewport_camera_b_query.first().?.id;
    try testing.expectEqual(camera_b, viewport_camera_b);
}

test "Database getEntityCount" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try testing.expectEqual(@as(usize, 0), db.getEntityCount());

    const entity1 = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    try testing.expectEqual(@as(usize, 1), db.getEntityCount());

    const entity2 = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 }, .health = Health{ .current = 100, .max = 100 } });
    try testing.expectEqual(@as(usize, 2), db.getEntityCount());

    try db.removeEntity(entity1);
    try testing.expectEqual(@as(usize, 1), db.getEntityCount());

    try db.removeEntity(entity2);
    try testing.expectEqual(@as(usize, 0), db.getEntityCount());
}

test "Database getArchetypeCount" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try testing.expectEqual(@as(usize, 0), db.getArchetypeCount());

    const entity1 = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });
    try testing.expectEqual(@as(usize, 1), db.getArchetypeCount());

    const entity2 = try db.createEntity(.{ .position = Position{ .x = 3.0, .y = 4.0 }, .health = Health{ .current = 100, .max = 100 } });
    try testing.expectEqual(@as(usize, 2), db.getArchetypeCount());

    const entity3 = try db.createEntity(.{ .position = Position{ .x = 5.0, .y = 6.0 } });
    try testing.expectEqual(@as(usize, 2), db.getArchetypeCount()); // Same archetype as entity1

    try db.removeEntity(entity1);
    try testing.expectEqual(@as(usize, 2), db.getArchetypeCount()); // Archetype still exists

    try db.removeEntity(entity3);
    try testing.expectEqual(@as(usize, 1), db.getArchetypeCount()); // Archetype pruned

    try db.removeEntity(entity2);
    try testing.expectEqual(@as(usize, 0), db.getArchetypeCount()); // All archetypes pruned
}

test "Database replace components with addComponents" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);

    // Replace Health component using addComponents
    try db.addComponents(entity_id, .{ .health = TestHealth.critical });

    // Entity should still be in the same archetype (Position + Health)
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;
    try testing.expectEqual(@as(usize, 2), archetype.columns.len);

    // Health component should be updated
    try testing.expectEqual(TestHealth.critical.current, entity.get(Health).?.current);
    try testing.expectEqual(TestHealth.critical.max, entity.get(Health).?.max);

    // Position component should remain unchanged
    try testing.expectEqual(TestPositions.basic.x, entity.get(Position).?.x);
    try testing.expectEqual(TestPositions.basic.y, entity.get(Position).?.y);
}

test "Database addComponent - singular doesn't require tuple" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });

    // Add Health component without tuple
    try db.addComponent(entity_id, Health{ .current = 100, .max = 100 });

    // Verify entity has both components
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 1.0), entity.get(Position).?.x);
    try testing.expectEqual(@as(i32, 100), entity.get(Health).?.current);
    try testing.expectEqual(@as(i32, 100), entity.get(Health).?.max);
}

test "Database removeComponent - singular doesn't require tuple" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 }, .health = Health{ .current = 100, .max = 100 } });

    // Remove Health component without tuple
    try db.removeComponent(entity_id, Health);

    // Verify entity only has Position component
    const entity = db.getEntity(entity_id).?;
    const archetype = db.archetypes.get(entity.archetype_id).?;
    try testing.expectEqual(@as(usize, 1), archetype.columns.len);

    try testing.expectEqual(@as(f32, 1.0), entity.get(Position).?.x);
    try testing.expectEqual(@as(?*Health, null), entity.get(Health));
}

test "Increase maximum component limit per createEntity call" {
    const Component1 = struct { id: u8 = 0 };
    const Component2 = struct { id: u8 = 0 };
    const Component3 = struct { id: u8 = 0 };
    const Component4 = struct { id: u8 = 0 };
    const Component5 = struct { id: u8 = 0 };
    const Component6 = struct { id: u8 = 0 };
    const Component7 = struct { id: u8 = 0 };
    const Component8 = struct { id: u8 = 0 };
    const Component9 = struct { id: u8 = 0 };
    const Component10 = struct { id: u8 = 0 };
    const Component11 = struct { id: u8 = 0 };
    const Component12 = struct { id: u8 = 0 };

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with 32 components
    _ = try db.createEntity(.{
        Component1{},
        Component2{},
        Component3{},
        Component4{},
        Component5{},
        Component6{},
        Component7{},
        Component8{},
        Component9{},
        Component10{},
        Component11{},
        Component12{},
    });
}

const OwnedCounter = struct {
    count: usize,
};

const Droppable = struct {
    counter: *OwnedCounter,

    const Self = @This();
    pub fn __drop__(self: *Self) void {
        self.counter.count += 1;
    }
};

test "Database component with __drop__" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var counter = OwnedCounter{ .count = 0 };
    const entity_id = try db.createEntity(.{ .droppable = Droppable{ .counter = &counter } });

    try testing.expectEqual(0, counter.count);

    try db.removeEntity(entity_id);
    try testing.expectEqual(1, counter.count);
}

test "Droppable __drop__ called on entity.set replacement" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var c = OwnedCounter{ .count = 0 };
    const eid = try db.createEntity(.{ .droppable = Droppable{ .counter = &c } });

    var e = db.getEntity(eid).?;
    try e.set(Droppable{ .counter = &c }); // replace same type
    try testing.expectEqual(@as(usize, 1), c.count);

    try db.removeEntity(eid);
    try testing.expectEqual(@as(usize, 2), c.count);
}

test "Droppable __drop__ on addComponents update" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var c = OwnedCounter{ .count = 0 };
    const eid = try db.createEntity(.{ .droppable = Droppable{ .counter = &c }, .marker = struct {}{} });

    const archetype_before = db.getEntity(eid).?.archetype_id;
    try db.addComponents(eid, .{ .droppable = Droppable{ .counter = &c } });
    try testing.expectEqual(@as(usize, 1), c.count);
    try testing.expectEqual(archetype_before, db.getEntity(eid).?.archetype_id);
}

test "Droppable __drop__ on removeComponents" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var c = OwnedCounter{ .count = 0 };
    const eid = try db.createEntity(.{ .droppable = Droppable{ .counter = &c }, .position = struct { x: i32 }{ .x = 1 } });

    try db.removeComponent(eid, Droppable);
    try testing.expectEqual(@as(usize, 1), c.count);
    try testing.expectEqual(@as(?*Droppable, null), db.getEntity(eid).?.get(Droppable));
}

test "Droppable __drop__ on swapRemove only drops removed index" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var c = OwnedCounter{ .count = 0 };
    const e1 = try db.createEntity(.{ Droppable{ .counter = &c } });
    const e2 = try db.createEntity(.{ Droppable{ .counter = &c } });
    const e3 = try db.createEntity(.{ Droppable{ .counter = &c } });

    try db.removeEntity(e2);
    try testing.expectEqual(@as(usize, 1), c.count);

    // Removing remaining entities should add two more drops
    try db.removeEntity(e1);
    try db.removeEntity(e3);
    try testing.expectEqual(@as(usize, 3), c.count);
}
