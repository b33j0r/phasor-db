const std = @import("std");
const testing = std.testing;

const root = @import("../root.zig");
const Database = root.Database;
const Transaction = root.Transaction;
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Health = fixtures.Health;
const Velocity = fixtures.Velocity;
const Marker = fixtures.Marker;
const LargeComponent = fixtures.LargeComponent;

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

test "ComponentArray memory leak - capacity growth and shrinkage" {
    const allocator = testing.allocator;

    const num_iterations = 50;
    const max_components = 1000;

    for (0..num_iterations) |_| {
        var component_array = ComponentArray.initFromType(
            allocator,
            componentId(Position),
            @sizeOf(Position),
            @alignOf(Position),
            null,
        );
        defer component_array.deinit();

        // Grow the array
        for (0..max_components) |i| {
            try component_array.append(Position{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2) });
        }

        // Shrink by removing elements
        while (component_array.len > 0) {
            component_array.swapRemove(component_array.len - 1);
        }

        // Test shrinkAndFree explicitly
        try component_array.shrinkAndFree(0);
    }
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

test "Resource management memory leak" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const num_cycles = 100;

    for (0..num_cycles) |cycle| {
        // Insert resources
        try db.insertResource(GameState{ .score = @intCast(cycle * 100), .level = @intCast(cycle % 10 + 1), .time_remaining = 60.0 });

        try db.insertResource(PlayerStats{ .experience = cycle * 1000, .gold = @intCast(cycle * 50), .inventory = [_]u32{0} ** 16 });

        // Access resources
        const game_state = db.getResource(GameState);
        try testing.expect(game_state != null);
        try testing.expectEqual(@as(u32, @intCast(cycle * 100)), game_state.?.score);

        // Remove resources
        _ = db.removeResource(GameState);
        _ = db.removeResource(PlayerStats);

        try testing.expect(!db.hasResource(GameState));
        try testing.expect(!db.hasResource(PlayerStats));
    }
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

test "Comprehensive memory leak detection - realistic game simulation" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const simulation_ticks = 100;
    const max_entities = 200;

    var active_entities = std.ArrayListUnmanaged(u64).empty;
    defer active_entities.deinit(allocator);

    for (0..simulation_ticks) |tick| {
        // Spawn new entities (like enemies or projectiles)
        if (active_entities.items.len < max_entities) {
            for (0..5) |i| {
                const entity_id = try db.createEntity(.{ .position = Position{ .x = @floatFromInt(tick * 10 + i), .y = @floatFromInt(i) }, .health = Health{ .current = 100, .max = 100 } });
                try active_entities.append(allocator, entity_id);
            }
        }

        // Every 10 ticks, add velocity to some entities
        if (tick % 10 == 0) {
            for (active_entities.items[0..@min(10, active_entities.items.len)]) |entity_id| {
                try db.addComponents(entity_id, .{ .velocity = Velocity{ .dx = 1.0, .dy = -0.5 } });
            }
        }

        // Every 15 ticks, remove some entities (like despawning)
        if (tick % 15 == 0 and active_entities.items.len > 10) {
            const entities_to_remove = active_entities.items.len / 4;
            for (0..entities_to_remove) |_| {
                const entity_id = active_entities.swapRemove(0);
                try db.removeEntity(entity_id);
            }
        }

        // Every 20 ticks, manage resources
        if (tick % 20 == 0) {
            try db.insertResource(GameState{ .score = @intCast(tick * 10), .level = @intCast(tick / 50 + 1), .time_remaining = 120.0 });
        }

        // Use transactions periodically
        if (tick % 25 == 0) {
            var tx = db.transaction();
            defer tx.deinit();

            // Queue some operations
            for (0..3) |i| {
                const entity_id = try tx.createEntity(.{ .position = Position{ .x = @floatFromInt(tick + i), .y = @floatFromInt(i * 5) } });
                try active_entities.append(allocator, entity_id);
            }

            try tx.execute();
        }
    }

    // Clean up remaining entities
    for (active_entities.items) |entity_id| {
        try db.removeEntity(entity_id);
    }

    // Final verification - database should be clean
    try testing.expectEqual(@as(usize, 0), db.entities.count());
}
