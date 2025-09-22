const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;
const Database = root.Database;
const Entity = root.Entity;
const fixtures = @import("fixtures.zig");
const TestEntity = fixtures.TestEntity;
const TestPositions = fixtures.TestPositions;
const TestHealth = fixtures.TestHealth;
const TestVelocity = fixtures.TestVelocity;
const Position = fixtures.Position;
const Health = fixtures.Health;
const Velocity = fixtures.Velocity;
const Without = root.Without;

test "QuerySpec first functionality" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Test no matching entities - should return null
    var empty_query = try db.query(.{Position});
    defer empty_query.deinit();
    try testing.expectEqual(@as(?root.Entity, null), empty_query.first());

    // Create entities with different component combinations
    _ = try db.createEntity(.{ .health = TestHealth.full }); // Only Health
    const positioned_id = try db.createEntity(TestEntity.basic_positioned); // Position only
    const combo_id = try db.createEntity(TestEntity.healthy_positioned); // Position + Health

    // Test single component query - should find positioned entities
    var pos_query = try db.query(.{Position});
    defer pos_query.deinit();
    const first_pos = pos_query.first();
    try testing.expect(first_pos != null);
    try testing.expect(first_pos.?.id == positioned_id or first_pos.?.id == combo_id);
    try testing.expect(first_pos.?.has(Position));

    // Test multi-component query - should only find entities with both
    var combo_query = try db.query(.{ Position, Health });
    defer combo_query.deinit();
    const first_combo = combo_query.first();
    try testing.expect(first_combo != null);
    try testing.expectEqual(combo_id, first_combo.?.id);
    try testing.expect(first_combo.?.has(Position));
    try testing.expect(first_combo.?.has(Health));
}

test "QuerySpec with traits - ComponentX matches Component1 and Component2" {
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

test "Database - query then groupBy" {
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

    const QueryComponent = struct {};

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create disjoint entities
    const entity1a_id = try db.createEntity(.{ Component1{}, QueryComponent{} });
    _ = try db.createEntity(.{Component1{}});
    const entity2a_id = try db.createEntity(.{ Component2{}, QueryComponent{} });

    // QuerySpec for entities with QueryComponent
    var query = try db.query(.{QueryComponent});
    defer query.deinit();

    try testing.expectEqual(2, query.count());

    // Group by ComponentN after querying
    var groups = try query.groupBy(ComponentN);
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

    try testing.expectEqual(entity1a_id, group1_iterator.next().?.id);
    try testing.expectEqual(null, group1_iterator.next());

    try testing.expectEqual(entity2a_id, group2_iterator.next().?.id);
    try testing.expectEqual(null, group2_iterator.next());
}

test "Database - GroupByResult iteration order 1" {
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

    // At this point, a small GroupByResult might look correct (3, 5, 8)

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
    try testing.expectEqual(@as(?*const root.GroupByResult.Group, null), group_iterator.next());
}

test "Database - GroupByResult iteration order 2" {
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

test "Database - Query Without" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different component combinations
    _ = try db.createEntity(.{ .health = TestHealth.full }); // Only Health
    const entity2_id = try db.createEntity(TestEntity.basic_positioned); // Position only
    _ = try db.createEntity(TestEntity.healthy_positioned); // Position + Health
    _ = try db.createEntity(.{ .velocity = TestVelocity.stationary }); // Only Velocity

    // Query for entities with Position but WITHOUT Health
    var query = try db.query(.{ Position, Without(Health) });
    defer query.deinit();

    try testing.expectEqual(1, query.count());

    var iter = query.iterator();
    const found_entity = iter.next() orelse null;
    try testing.expect(found_entity != null);
    try testing.expectEqual(entity2_id, found_entity.?.id);
    try testing.expect(found_entity.?.has(Position));
    try testing.expect(!found_entity.?.has(Health));
}

test "QueryResult listAlloc functionality" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create some entities with positions
    const entity1_id = try db.createEntity(TestEntity.basic_positioned);
    const entity2_id = try db.createEntity(TestEntity.basic_positioned);
    const entity3_id = try db.createEntity(TestEntity.healthy_positioned);

    // Create a query that will match all positioned entities
    var query = try db.query(.{Position});
    defer query.deinit();

    // Should find 3 entities
    try testing.expectEqual(@as(usize, 3), query.count());

    // Get a list of all entities using listAlloc
    const entity_list = try query.listAlloc(allocator);
    defer allocator.free(entity_list);

    // Verify the list has the correct length
    try testing.expectEqual(@as(usize, 3), entity_list.len);

    // Check that all entities in the list have the Position component
    for (entity_list) |entity| {
        try testing.expect(entity.has(Position));
    }

    // Verify the list contains all the expected entity IDs
    var found_entity1 = false;
    var found_entity2 = false;
    var found_entity3 = false;

    for (entity_list) |entity| {
        if (entity.id == entity1_id) found_entity1 = true;
        if (entity.id == entity2_id) found_entity2 = true;
        if (entity.id == entity3_id) found_entity3 = true;
    }

    try testing.expect(found_entity1);
    try testing.expect(found_entity2);
    try testing.expect(found_entity3);
}

test "QueryResult sortAlloc functionality" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // Create entities with different health values
    // We use the predefined TestHealth constants to create entities
    const entity1_id = try db.createEntity(.{
        .position = TestPositions.origin,
        .health = TestHealth.damaged, // Medium health (50)
    });

    const entity2_id = try db.createEntity(.{
        .position = TestPositions.origin,
        .health = TestHealth.full, // Full health (100)
    });

    const entity3_id = try db.createEntity(.{
        .position = TestPositions.origin,
        .health = TestHealth.critical, // Low health (10)
    });

    // Create a query for entities with health
    var query = try db.query(.{Health});
    defer query.deinit();

    // Should find 3 entities
    try testing.expectEqual(@as(usize, 3), query.count());

    // Define sort context for sorting by health in ascending order
    const HealthSortContext = struct {
        pub fn lessThan(_: @This(), a: Entity, b: Entity) bool {
            const health_a = a.get(Health).?.current;
            const health_b = b.get(Health).?.current;
            return health_a < health_b;
        }
    };

    const sort_ctx = HealthSortContext{};

    // Get a sorted list of entities by health (ascending)
    const sorted_entities = try query.sortAlloc(allocator, sort_ctx);
    defer allocator.free(sorted_entities);

    // Verify we got the right number of entities
    try testing.expectEqual(@as(usize, 3), sorted_entities.len);

    // Verify the entities are sorted by health in ascending order
    try testing.expectEqual(entity3_id, sorted_entities[0].id); // Low health (10)
    try testing.expectEqual(entity1_id, sorted_entities[1].id); // Medium health (50)
    try testing.expectEqual(entity2_id, sorted_entities[2].id); // Full health (100)

    // Check that the health values are actually in sorted order
    for (0..sorted_entities.len - 1) |i| {
        const health_current = sorted_entities[i].get(Health).?.current;
        const health_next = sorted_entities[i + 1].get(Health).?.current;
        try testing.expect(health_current <= health_next);
    }

    // Test sorting in descending order
    const HealthDescendingSortContext = struct {
        pub fn lessThan(_: @This(), a: Entity, b: Entity) bool {
            const health_a = a.get(Health).?.current;
            const health_b = b.get(Health).?.current;
            // Reverse the comparison for descending order
            return health_a > health_b;
        }
    };

    const desc_sort_ctx = HealthDescendingSortContext{};

    // Get a sorted list of entities by health (descending)
    const sorted_desc_entities = try query.sortAlloc(allocator, desc_sort_ctx);
    defer allocator.free(sorted_desc_entities);

    // Verify the entities are sorted by health in descending order
    try testing.expectEqual(entity2_id, sorted_desc_entities[0].id); // Full health (100)
    try testing.expectEqual(entity1_id, sorted_desc_entities[1].id); // Medium health (75)
    try testing.expectEqual(entity3_id, sorted_desc_entities[2].id); // Low health (25)
}
