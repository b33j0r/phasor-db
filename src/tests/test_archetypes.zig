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
    defer archetype.deinit();

    const position_index = archetype.getColumnIndexByType(Position).?;
    const health_index = archetype.getColumnIndexByType(Health).?;

    try testing.expectEqual(2, archetype.columns.len);
    try testing.expectEqual(componentId(Position), archetype.columns[position_index].id);
    try testing.expectEqual(componentId(Health), archetype.columns[health_index].id);
    try testing.expectEqual(0, archetype.entity_ids.items.len);
}

test "Archetype calculateId" {
    const allocator = std.testing.allocator;
    const archetype_id = Archetype.calculateId(.{
        Position{
            .x = 0.0,
            .y = 0.0,
        },
        Health{
            .max = 100,
            .current = 50,
        },
    });

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
    defer archetype.deinit();

    try testing.expectEqual(archetype_id, archetype.id);

}

test "Archetype calculateIdSetUnion" {
    const allocator = std.testing.allocator;

    // Test case 1: Union with no duplicates
    {
        // Create archetype with Position and Health
        var archetype = try Archetype.fromComponents(allocator, .{
            .position = Position{ .x = 0, .y = 0 },
            .health = Health{ .current = 100, .max = 100 },
        });
        defer archetype.deinit();

        // Calculate union with Velocity and Marker (no overlap)
        const union_id = archetype.calculateIdSetUnion(.{
            .velocity = Velocity{ .dx = 1.0, .dy = 1.0 },
            .marker = Marker{},
        });

        // Calculate expected ID by creating archetype with all components
        const expected_id = Archetype.calculateId(.{
            .position = Position{ .x = 0, .y = 0 },
            .health = Health{ .current = 100, .max = 100 },
            .velocity = Velocity{ .dx = 1.0, .dy = 1.0 },
            .marker = Marker{},
        });

        try std.testing.expectEqual(expected_id, union_id);
    }

    // Test case 2: Union with duplicates
    {
        // Create archetype with Position, Health, and Marker
        var archetype = try Archetype.fromComponents(allocator, .{
            .position = Position{ .x = 0, .y = 0 },
            .health = Health{ .current = 100, .max = 100 },
            .marker = Marker{},
        });
        defer archetype.deinit();

        // Calculate union with Health and Velocity (Health is duplicate)
        const union_id = archetype.calculateIdSetUnion(.{
            .health = Health{ .current = 50, .max = 75 }, // Duplicate
            .velocity = Velocity{ .dx = 1.0, .dy = 1.0 }, // New
        });

        // Expected result should have Position, Health, Marker, Velocity (Health only once)
        const expected_id = Archetype.calculateId(.{
            .position = Position{ .x = 0, .y = 0 },
            .health = Health{ .current = 100, .max = 100 },
            .marker = Marker{},
            .velocity = Velocity{ .dx = 1.0, .dy = 1.0 },
        });

        try std.testing.expectEqual(expected_id, union_id);
    }

    // Test case 3: Union with all duplicates
    {
        // Create archetype with Position and Health
        var archetype = try Archetype.fromComponents(allocator, .{
            .position = Position{ .x = 10, .y = 20 },
            .health = Health{ .current = 80, .max = 100 },
        });
        defer archetype.deinit();

        // Calculate union with same components (all duplicates)
        const union_id = archetype.calculateIdSetUnion(.{
            .position = Position{ .x = 5, .y = 15 }, // Different values, same type
            .health = Health{ .current = 60, .max = 90 }, // Different values, same type
        });

        // Expected result should be the same as the original archetype ID
        try std.testing.expectEqual(archetype.id, union_id);
    }

    // Test case 4: Union with empty components
    {
        // Create archetype with Position
        var archetype = try Archetype.fromComponents(allocator, .{
            .position = Position{ .x = 1, .y = 2 },
        });
        defer archetype.deinit();

        // Calculate union with empty struct (should add it)
        const union_id = archetype.calculateIdSetUnion(.{
            .marker = Marker{},
        });

        // Expected result should have Position and Marker
        const expected_id = Archetype.calculateId(.{
            .position = Position{ .x = 1, .y = 2 },
            .marker = Marker{},
        });

        try std.testing.expectEqual(expected_id, union_id);
    }

    // Test case 5: Single component archetype with single new component
    {
        // Create archetype with just Marker
        var archetype = try Archetype.fromComponents(allocator, .{
            .marker = Marker{},
        });
        defer archetype.deinit();

        // Calculate union with Position
        const union_id = archetype.calculateIdSetUnion(.{
            .position = Position{ .x = 3, .y = 4 },
        });

        // Expected result should have Marker and Position
        const expected_id = Archetype.calculateId(.{
            .marker = Marker{},
            .position = Position{ .x = 3, .y = 4 },
        });

        try std.testing.expectEqual(expected_id, union_id);
    }

    // Test case 6: Verify component order doesn't matter
    {
        // Create archetype with components in one order
        var archetype = try Archetype.fromComponents(allocator, .{
            .velocity = Velocity{ .dx = 1, .dy = 2 },
            .position = Position{ .x = 5, .y = 6 },
        });
        defer archetype.deinit();

        // Calculate union with components in different order
        const union_id = archetype.calculateIdSetUnion(.{
            .marker = Marker{},
            .health = Health{ .current = 30, .max = 50 },
        });

        // Expected result (order shouldn't matter due to sorting)
        const expected_id = Archetype.calculateId(.{
            .health = Health{ .current = 30, .max = 50 },
            .marker = Marker{},
            .position = Position{ .x = 5, .y = 6 },
            .velocity = Velocity{ .dx = 1, .dy = 2 },
        });

        try std.testing.expectEqual(expected_id, union_id);
    }
}

test "Archetype create with different order of components is the same" {
    const allocator = std.testing.allocator;
    var archetype1 = try Archetype.fromComponents(allocator, .{
        Position{
            .x = 0.0,
            .y = 0.0,
        },
        Health{
            .max = 100,
            .current = 50,
        },
    });
    defer archetype1.deinit();

    var archetype2 = try Archetype.fromComponents(allocator, .{
        Health{
            .max = 100,
            .current = 50,
        },
        Position{
            .x = 0.0,
            .y = 0.0,
        },
    });
    defer archetype2.deinit();

    try testing.expectEqual(archetype1.id, archetype2.id);
}

test "Archetype addEntity" {
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
    defer archetype.deinit();

    const entity_index = try archetype.addEntity(10, .{
        Position{
            .x = 1.0,
            .y = 2.0,
        },
        Health{
            .max = 200,
            .current = 150,
        },
    });

    const position_index = archetype.getColumnIndexByType(Position).?;
    const health_index = archetype.getColumnIndexByType(Health).?;

    try testing.expectEqual(1, archetype.entity_ids.items.len);
    try testing.expectEqual(10, archetype.entity_ids.items[entity_index]);
    try testing.expectEqual(1, archetype.columns[position_index].len);
    try testing.expectEqual(1, archetype.columns[health_index].len);

    const position = archetype.columns[position_index].get(entity_index, Position).?;
    const health = archetype.columns[health_index].get(entity_index, Health).?;

    try testing.expectEqual(1.0, position.x);
    try testing.expectEqual(2.0, position.y);
    try testing.expectEqual(200, health.max);
    try testing.expectEqual(150, health.current);
}

test "Archetype removeEntityByIndex" {
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
    defer archetype.deinit();

    _ = try archetype.addEntity(10, .{
        Position{
            .x = 1.0,
            .y = 2.0,
        },
        Health{
            .max = 200,
            .current = 150,
        },
    });

    _ = try archetype.addEntity(20, .{
        Position{
            .x = 3.0,
            .y = 4.0,
        },
        Health{
            .max = 300,
            .current = 250,
        },
    });

    const removed_entity_id = try archetype.removeEntityByIndex(0);
    try testing.expectEqual(10, removed_entity_id);

    try testing.expectEqual(1, archetype.entity_ids.items.len);
    try testing.expectEqual(20, archetype.entity_ids.items[0]);
}
