const std = @import("std");
const testing = std.testing;

const root = @import("../root.zig");
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

test "Entity has - component exists" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);
    const entity = db.getEntity(entity_id).?;

    // Test that entity has the components it was created with
    try testing.expect(entity.has(Position));
    try testing.expect(entity.has(Health));
}

test "Entity has - component does not exist" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with only Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    const entity = db.getEntity(entity_id).?;

    // Test that entity has Position but not other components
    try testing.expect(entity.has(Position));
    try testing.expect(!entity.has(Health));
    try testing.expect(!entity.has(Velocity));
    try testing.expect(!entity.has(Marker));
}

test "Entity has - different component types" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Test with full entity containing multiple components
    const full_entity_id = try db.createEntity(TestEntity.full_entity);
    const full_entity = db.getEntity(full_entity_id).?;

    try testing.expect(full_entity.has(Position));
    try testing.expect(full_entity.has(Health));
    try testing.expect(full_entity.has(Velocity));
    try testing.expect(!full_entity.has(Marker));
    try testing.expect(!full_entity.has(LargeComponent));

    // Test with entity containing only Marker (zero-sized component)
    const marker_entity_id = try db.createEntity(.{ .marker = Marker{} });
    const marker_entity = db.getEntity(marker_entity_id).?;

    try testing.expect(marker_entity.has(Marker));
    try testing.expect(!marker_entity.has(Position));
    try testing.expect(!marker_entity.has(Health));
}

test "Entity set - successful value setting" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position and Health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);
    var entity = db.getEntity(entity_id).?;

    // Test setting Position component
    try entity.set(TestPositions.alternative);
    const updated_position = entity.get(Position).?;
    try testing.expectEqual(TestPositions.alternative.x, updated_position.x);
    try testing.expectEqual(TestPositions.alternative.y, updated_position.y);

    // Test setting Health component
    try entity.set(TestHealth.damaged);
    const updated_health = entity.get(Health).?;
    try testing.expectEqual(TestHealth.damaged.current, updated_health.current);
    try testing.expectEqual(TestHealth.damaged.max, updated_health.max);
}

test "Entity set - error conditions" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with only Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    var entity = db.getEntity(entity_id).?;

    // Test setting a component that doesn't exist - should return ComponentNotFound
    const result = entity.set(TestVelocity.moving_right);
    try testing.expectError(error.ComponentNotFound, result);

    // Verify original component still works
    try entity.set(TestPositions.third);
    const position = entity.get(Position).?;
    try testing.expectEqual(TestPositions.third.x, position.x);
    try testing.expectEqual(TestPositions.third.y, position.y);
}

test "Entity set - different component types" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Test with various component types
    const entity_id = try db.createEntity(.{
        .position = TestPositions.basic,
        .health = TestHealth.full,
        .marker = Marker{},
        .large_component = LargeComponent{},
    });
    var entity = db.getEntity(entity_id).?;

    // Test setting different types
    try entity.set(TestPositions.origin);
    try entity.set(TestHealth.critical);
    try entity.set(Marker{});

    const large_comp = LargeComponent{ .data = [_]u8{1} ** 1024, .id = 999 };
    try entity.set(large_comp);

    // Verify all values were set correctly
    try testing.expectEqual(TestPositions.origin.x, entity.get(Position).?.x);
    try testing.expectEqual(TestHealth.critical.current, entity.get(Health).?.current);
    try testing.expectEqual(@as(u64, 999), entity.get(LargeComponent).?.id);
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
    try db.removeComponents(entity_id, .{ .health = TestHealth.critical });

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

    // Query for entities with Position
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

    // Query for entities with both Position and Health
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

    // Create an entity with Position
    const entity_id = try db.createEntity(.{ .position = Position{ .x = 1.0, .y = 2.0 } });

    // Add Health component with runtime values
    const health_current: i32 = 50; // Not comptime-known
    const health_max: i32 = 100; // Not comptime-known

    try db.addComponents(entity_id, .{
        Health{ .current = health_current, .max = health_max },
    });

    // Verify entity has both components
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(@as(f32, 1.0), entity.get(Position).?.x);
    try testing.expectEqual(@as(i32, 50), entity.get(Health).?.current);
    try testing.expectEqual(@as(i32, 100), entity.get(Health).?.max);
}
