const std = @import("std");
const testing = std.testing;
const root = @import("../root.zig");
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

test "Query first - no matching entities" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create some entities without Position component
    _ = try db.createEntity(.{ .health = TestHealth.full });
    _ = try db.createEntity(.{ .velocity = TestVelocity.moving_right });

    // Query for entities with Position (none exist)
    var query = try db.query(.{Position});
    defer query.deinit();

    // first() should return null when no entities match
    const first_entity = query.first();
    try testing.expectEqual(@as(?root.Entity, null), first_entity);
}

test "Query first - one matching entity" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different components
    _ = try db.createEntity(.{ .health = TestHealth.full }); // No Position
    const positioned_entity_id = try db.createEntity(TestEntity.basic_positioned);
    _ = try db.createEntity(.{ .velocity = TestVelocity.moving_right }); // No Position

    // Query for entities with Position (only one exists)
    var query = try db.query(.{Position});
    defer query.deinit();

    // first() should return the only matching entity
    const first_entity = query.first();
    try testing.expect(first_entity != null);
    try testing.expectEqual(positioned_entity_id, first_entity.?.id);

    // Verify the entity has the expected Position component
    const pos = first_entity.?.get(Position);
    try testing.expect(pos != null);
    try testing.expectEqual(TestPositions.basic.x, pos.?.x);
    try testing.expectEqual(TestPositions.basic.y, pos.?.y);
}

test "Query first - multiple matching entities" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create multiple entities with Position component
    const entity1_id = try db.createEntity(.{ .position = TestPositions.basic });
    const entity2_id = try db.createEntity(.{ .position = TestPositions.alternative });
    const entity3_id = try db.createEntity(.{ .position = TestPositions.third });

    // Query for entities with Position (all three match)
    var query = try db.query(.{Position});
    defer query.deinit();

    // first() should return the first entity that matches
    const first_entity = query.first();
    try testing.expect(first_entity != null);

    // The first entity should be one of the created entities
    // (the exact order depends on internal implementation)
    const first_id = first_entity.?.id;
    try testing.expect(first_id == entity1_id or first_id == entity2_id or first_id == entity3_id);

    // Verify the entity has a Position component
    const pos = first_entity.?.get(Position);
    try testing.expect(pos != null);

    // Verify consistency: calling first() multiple times should return the same entity
    const second_call = query.first();
    try testing.expect(second_call != null);
    try testing.expectEqual(first_id, second_call.?.id);
}

test "Query first - multiple components query" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different component combinations
    _ = try db.createEntity(TestEntity.basic_positioned); // Only Position
    _ = try db.createEntity(.{ .health = TestHealth.full }); // Only Health
    const matching_entity1_id = try db.createEntity(TestEntity.healthy_positioned); // Position + Health
    const matching_entity2_id = try db.createEntity(.{ .position = TestPositions.alternative, .health = TestHealth.damaged }); // Position + Health

    // Query for entities with both Position and Health
    var query = try db.query(.{ Position, Health });
    defer query.deinit();

    // first() should return one of the matching entities
    const first_entity = query.first();
    try testing.expect(first_entity != null);

    const first_id = first_entity.?.id;
    try testing.expect(first_id == matching_entity1_id or first_id == matching_entity2_id);

    // Verify the entity has both components
    try testing.expect(first_entity.?.get(Position) != null);
    try testing.expect(first_entity.?.get(Health) != null);
}

test "Query with traits - ComponentX matches Component1 and Component2" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                n: i32 = N,
                pub const __trait__ = ComponentX;
            };
        }

        pub const ComponentX = struct {
            n: i32,
        };
    };
    const Component = ComponentTypeFactory.Component;
    const ComponentX = ComponentTypeFactory.ComponentX;
    const Component1 = Component(1);
    const Component2 = Component(2);

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with Component1 and Component2
    _ = try db.createEntity(.{Component1{}});
    _ = try db.createEntity(.{Component2{}});

    // The query for ComponentX should match Component1 and Component2
    // since they are both defined with the same __traits__
    var query = try db.query(.{ComponentX});
    defer query.deinit();

    try testing.expectEqual(2, query.count());
    var iter = query.iterator();
    var found_component1 = false;
    var found_component2 = false;

    while (iter.next()) |entity| {
        const comp = entity.get(ComponentX);
        try testing.expect(comp != null);

        if (comp.?.n == 1) {
            found_component1 = true;
        } else if (comp.?.n == 2) {
            found_component2 = true;
        } else {
            // Should not find other values
            try testing.expect(false);
        }
    }

    try testing.expect(found_component1);
    try testing.expect(found_component2);
}

test "Database groupBy" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                pub const __group_key__ = N;
                pub const __trait__ = ComponentN;
            };
        }

        pub const ComponentN = struct {};
    };
    const Component = ComponentTypeFactory.Component;
    const ComponentN = ComponentTypeFactory.ComponentN;

    const Component1 = Component(1);
    const Component2 = Component(2);

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different components
    const entity1a_id = try db.createEntity(.{Component1{}});
    const entity1b_id = try db.createEntity(.{Component1{}});
    const entity2a_id = try db.createEntity(.{Component2{}});

    // Group by ComponentN
    var groups = try db.groupBy(ComponentN);
    defer groups.deinit();

    try testing.expectEqual(2, groups.count());

    var group_iterator = groups.iterator();
    const group1 = group_iterator.next().?;
    const group2 = group_iterator.next().?;

    try testing.expectEqual(null, group_iterator.next());

    try testing.expectEqual(1, group1.key);
    try testing.expectEqual(2, group2.key);

    try testing.expectEqual(componentId(Component1), group1.component_id);
    try testing.expectEqual(componentId(Component2), group2.component_id);

    var group1_iterator = group1.iterator();
    var group2_iterator = group2.iterator();

    try testing.expect(group1_iterator.next().?.id == entity1a_id);
    try testing.expect(group1_iterator.next().?.id == entity1b_id);
    try testing.expectEqual(null, group1_iterator.next());

    try testing.expect(group2_iterator.next().?.id == entity2a_id);
    try testing.expectEqual(null, group2_iterator.next());
}

test "GroupBy iteration order regression - heap order disruption" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                value: i32 = N,
                pub const __group_key__ = N;
                pub const __trait__ = ComponentN;
            };
        }

        pub const ComponentN = struct {
            value: i32,
        };
    };
    const Component = ComponentTypeFactory.Component;
    const ComponentN = ComponentTypeFactory.ComponentN;

    // Create components with keys that will expose heap ordering issues
    // These keys are chosen to trigger different heap orderings as more are added
    const Component5 = Component(5);
    const Component3 = Component(3);
    const Component8 = Component(8);
    const Component1 = Component(1);
    const Component9 = Component(9);
    const Component2 = Component(2);
    const Component7 = Component(7);

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Add entities in an order that will cause heap reordering
    // This simulates "adding more layers" that disrupts the natural order
    _ = try db.createEntity(.{Component5{}});
    _ = try db.createEntity(.{Component3{}});
    _ = try db.createEntity(.{Component8{}});

    // At this point, a small GroupBy might look correct (3, 5, 8)

    // Add more entities to trigger heap reorganization
    _ = try db.createEntity(.{Component1{}});
    _ = try db.createEntity(.{Component9{}});
    _ = try db.createEntity(.{Component2{}});
    _ = try db.createEntity(.{Component7{}});

    // Group by ComponentN - this should return groups in key order
    var groups = try db.groupBy(ComponentN);
    defer groups.deinit();

    try testing.expectEqual(7, groups.count());

    // The critical test: groups MUST be returned in ascending key order
    // This is what was broken when the heap order took over
    var group_iterator = groups.iterator();

    const group1 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 1), group1.key);

    const group2 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 2), group2.key);

    const group3 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 3), group3.key);

    const group4 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 5), group4.key);

    const group5 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 7), group5.key);

    const group6 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 8), group6.key);

    const group7 = group_iterator.next().?;
    try testing.expectEqual(@as(i32, 9), group7.key);

    // Should be no more groups
    try testing.expectEqual(@as(?*const root.GroupBy.Group, null), group_iterator.next());
}

test "GroupBy iteration order - stress test with many groups" {
    const ComponentTypeFactory = struct {
        pub fn Component(N: i32) type {
            return struct {
                value: i32 = N,
                pub const __group_key__ = N;
                pub const __trait__ = ComponentN;
            };
        }

        pub const ComponentN = struct {
            value: i32,
        };
    };

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create components with random-ish keys to stress test heap behavior
    const keys = [_]i32{ 42, 7, 99, 13, 3, 88, 21, 56, 1, 77, 34, 65, 12, 91, 28 };

    // Add entities in the order that maximizes heap disruption
    inline for (keys) |key| {
        const ComponentType = ComponentTypeFactory.Component(key);
        _ = try db.createEntity(.{ComponentType{}});
    }

    var groups = try db.groupBy(ComponentTypeFactory.ComponentN);
    defer groups.deinit();

    try testing.expectEqual(keys.len, groups.count());

    // Collect all keys from iteration
    var iterated_keys: [keys.len]i32 = undefined;
    var group_iterator = groups.iterator();
    var i: usize = 0;

    while (group_iterator.next()) |group| {
        try testing.expect(i < keys.len);
        iterated_keys[i] = group.key;
        i += 1;
    }

    try testing.expectEqual(keys.len, i);

    // Verify keys are in ascending order (this is what the bug broke)
    for (1..iterated_keys.len) |idx| {
        try testing.expect(iterated_keys[idx - 1] < iterated_keys[idx]);
    }

    // Also verify we got exactly the expected keys
    var sorted_expected = keys;
    std.sort.pdq(i32, &sorted_expected, {}, std.sort.asc(i32));

    for (iterated_keys, sorted_expected) |actual, expected| {
        try testing.expectEqual(expected, actual);
    }
}
