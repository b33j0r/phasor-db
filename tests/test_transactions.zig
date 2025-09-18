const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;
const Database = root.Database;
const Transaction = root.Transaction;
const fixtures = @import("fixtures.zig");
const TestEntity = fixtures.TestEntity;
const TestPositions = fixtures.TestPositions;
const TestHealth = fixtures.TestHealth;
const TestVelocity = fixtures.TestVelocity;
const Position = fixtures.Position;
const Health = fixtures.Health;
const Velocity = fixtures.Velocity;

test "Transaction - basic creation and execution" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var txn = db.transaction();
    defer txn.deinit();

    // Transaction should be empty initially
    try testing.expectEqual(@as(usize, 0), txn.commands.items.len);

    // Execute empty transaction (should not crash)
    try txn.execute();
}

test "Transaction - deferred entity creation" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var txn = db.transaction();
    defer txn.deinit();

    // Create entity in transaction - should return valid ID but not create entity yet
    const entity_id = try txn.createEntity(TestEntity.basic_positioned);
    try testing.expectEqual(@as(usize, 1), txn.commands.items.len);

    // Entity should not exist in database yet
    try testing.expect(db.getEntity(entity_id) == null);
    try testing.expectEqual(@as(usize, 0), db.entities.count());

    // Execute transaction
    try txn.execute();

    // Now entity should exist in database
    const entity = db.getEntity(entity_id);
    try testing.expect(entity != null);
    try testing.expectEqual(@as(usize, 1), db.entities.count());
    try testing.expectEqual(TestPositions.basic.x, entity.?.get(Position).?.x);
    try testing.expectEqual(TestPositions.basic.y, entity.?.get(Position).?.y);

    // Commands should be cleared after execution
    try testing.expectEqual(@as(usize, 0), txn.commands.items.len);
}

test "Transaction - deferred entity removal" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entity directly in database first
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    try testing.expect(db.getEntity(entity_id) != null);
    try testing.expectEqual(@as(usize, 1), db.entities.count());

    var txn = db.transaction();
    defer txn.deinit();

    // Queue entity removal in transaction
    try txn.removeEntity(entity_id);
    try testing.expectEqual(@as(usize, 1), txn.commands.items.len);

    // Entity should still exist before execution
    try testing.expect(db.getEntity(entity_id) != null);
    try testing.expectEqual(@as(usize, 1), db.entities.count());

    // Execute transaction
    try txn.execute();

    // Now entity should be removed
    try testing.expect(db.getEntity(entity_id) == null);
    try testing.expectEqual(@as(usize, 0), db.entities.count());
}

test "Transaction - deferred component addition" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entity with just position
    const entity_id = try db.createEntity(TestEntity.basic_positioned);
    try testing.expect(db.getEntity(entity_id).?.get(Health) == null);

    var txn = db.transaction();
    defer txn.deinit();

    // Queue adding health component
    try txn.addComponents(entity_id, .{TestHealth.full});
    try testing.expectEqual(@as(usize, 1), txn.commands.items.len);

    // Entity should not have health component yet
    try testing.expect(db.getEntity(entity_id).?.get(Health) == null);

    // Execute transaction
    try txn.execute();

    // Now entity should have health component
    const entity = db.getEntity(entity_id).?;
    const health = entity.get(Health).?;
    try testing.expectEqual(TestHealth.full.current, health.current);
    try testing.expectEqual(TestHealth.full.max, health.max);
}

test "Transaction - deferred component removal" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entity with position and health
    const entity_id = try db.createEntity(TestEntity.healthy_positioned);
    try testing.expect(db.getEntity(entity_id).?.get(Health) != null);

    var txn = db.transaction();
    defer txn.deinit();

    // Queue removing health component
    try txn.removeComponents(entity_id, .{TestHealth.full});
    try testing.expectEqual(@as(usize, 1), txn.commands.items.len);

    // Entity should still have health component before execution
    try testing.expect(db.getEntity(entity_id).?.get(Health) != null);

    // Execute transaction
    try txn.execute();

    // Now entity should not have health component
    const entity = db.getEntity(entity_id).?;
    try testing.expect(entity.get(Health) == null);
    try testing.expect(entity.get(Position) != null); // Position should remain
}

test "Transaction - multiple deferred commands" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var txn = db.transaction();
    defer txn.deinit();

    // Queue multiple operations
    const entity1_id = try txn.createEntity(TestEntity.basic_positioned);
    const entity2_id = try txn.createEntity(TestEntity.healthy_positioned);
    try txn.addComponents(entity1_id, .{TestHealth.damaged});
    try txn.addComponents(entity2_id, .{TestVelocity.moving_right});

    try testing.expectEqual(@as(usize, 4), txn.commands.items.len);

    // No entities should exist yet
    try testing.expectEqual(@as(usize, 0), db.entities.count());

    // Execute all commands
    try txn.execute();

    // All operations should be completed
    try testing.expectEqual(@as(usize, 2), db.entities.count());

    const entity1 = db.getEntity(entity1_id).?;
    try testing.expect(entity1.get(Position) != null);
    try testing.expect(entity1.get(Health) != null);
    try testing.expectEqual(TestHealth.damaged.current, entity1.get(Health).?.current);

    const entity2 = db.getEntity(entity2_id).?;
    try testing.expect(entity2.get(Position) != null);
    try testing.expect(entity2.get(Health) != null);
    try testing.expect(entity2.get(Velocity) != null);
    try testing.expectEqual(TestVelocity.moving_right.dx, entity2.get(Velocity).?.dx);
}

test "Transaction - immediate query operations" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create some entities directly in database
    const existing_entity = try db.createEntity(TestEntity.basic_positioned);

    var txn = db.transaction();
    defer txn.deinit();

    // Immediate operations should work (passthrough to db)
    try testing.expect(txn.getEntity(existing_entity) != null);

    var query = try txn.query(.{Position});
    defer query.deinit();
    try testing.expectEqual(@as(usize, 1), query.count());

    // Queue a deferred operation
    _ = try txn.createEntity(TestEntity.healthy_positioned);

    // Immediate query should still only see existing entities
    var query2 = try txn.query(.{Position});
    defer query2.deinit();
    try testing.expectEqual(@as(usize, 1), query2.count());

    // After execution, query should see both entities
    try txn.execute();

    var query3 = try txn.query(.{Position});
    defer query3.deinit();
    try testing.expectEqual(@as(usize, 2), query3.count());
}

test "Transaction - double execute should fail" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var txn = db.transaction();
    defer txn.deinit();

    // Create an entity in the transaction
    _ = try txn.createEntity(TestEntity.basic_positioned);

    // Execute first time - should succeed
    try txn.execute();

    // Now try to execute again - should fail
    const result = txn.execute();
    try testing.expectError(error.TransactionAlreadyExecuted, result);
}

test "Transaction memory leak - deferred command cleanup" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const num_transactions = 100;
    const commands_per_transaction = 20;

    for (0..num_transactions) |_| {
        // Test 1: Transactions that are executed
        {
            var tx = db.transaction();
            defer tx.deinit();

            for (0..commands_per_transaction) |i| {
                _ = try tx.createEntity(.{ .position = Position{ .x = @floatFromInt(i), .y = 0.0 } });
            }

            try tx.execute();
        }

        // Test 2: Transactions that are NOT executed (should clean up contexts)
        {
            var tx = db.transaction();
            defer tx.deinit();

            for (0..commands_per_transaction) |i| {
                _ = try tx.createEntity(.{ .health = Health{ .current = @intCast(i), .max = 100 } });
            }
            // NOT calling tx.execute() - contexts should be cleaned up in deinit()
        }
    }
}
