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

test "Database addComponents - add existing component (no-op)" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create an entity with Position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    const original_archetype_count = db.archetypes.count();

    // Try to add Position again - should be a no-op
    try db.addComponents(entity_id, .{ .position = TestPositions.alternative });

    // Should still have the same number of archetypes
    try testing.expectEqual(original_archetype_count, db.archetypes.count());
    
    // Entity should still have original position (no-op)
    const entity = db.getEntity(entity_id).?;
    try testing.expectEqual(TestPositions.basic.x, entity.get(Position).?.x);
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
    try db.addComponents(entity_id, .{ 
        .health = Health{ .current = 100, .max = 100 },
        .velocity = Velocity{ .dx = 0.5, .dy = -0.5 }
    });
    
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
