const std = @import("std");
const testing = std.testing;
const root = @import("../root.zig");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
const Health = fixtures.Health;
const Marker = fixtures.Marker;
const LargeComponent = fixtures.LargeComponent;
const createPositionArray = fixtures.createPositionArray;
const createHealthArray = fixtures.createHealthArray;
const createMarkerArray = fixtures.createMarkerArray;
const createPopulatedArray = fixtures.createPopulatedArray;
const TestPositions = fixtures.TestPositions;
const TestHealth = fixtures.TestHealth;

test "componentId is consistent" {
    const pos_id1 = componentId(Position);
    const pos_id2 = componentId(Position);

    try testing.expectEqual(pos_id1, pos_id2);
}

test "componentId generates unique identifiers from types" {
    const pos_id = componentId(Position);
    const health_id = componentId(Health);
    const empty_id = componentId(Marker);

    try testing.expect(pos_id != health_id);
    try testing.expect(health_id != empty_id);
    try testing.expect(pos_id != empty_id);

    // Same type should generate same ID
    try testing.expectEqual(pos_id, componentId(Position));
}

test "componentId generates unique identifiers from values" {
    const pos_id = componentId(TestPositions.basic);
    const health_id = componentId(TestHealth.high_max);
    const empty_id = componentId(Marker{});

    try testing.expect(pos_id != health_id);
    try testing.expect(health_id != empty_id);
    try testing.expect(pos_id != empty_id);

    // Same value should generate same ID
    try testing.expectEqual(pos_id, componentId(TestPositions.basic));
}

test "componentId generates the same ID from a value and its type" {
    const pos_id = componentId(TestPositions.basic);
    const pos_type_id = componentId(Position);

    try testing.expectEqual(pos_id, pos_type_id);
}

test "ComponentArray initialization and deinitialization" {
    const allocator = testing.allocator;

    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    try testing.expectEqual(componentId(Position), pos_array.meta.id);
    try testing.expectEqual(@sizeOf(Position), pos_array.meta.size);
    try testing.expectEqual(@alignOf(Position), pos_array.meta.alignment);
    try testing.expectEqual(std.mem.alignForward(usize, @sizeOf(Position), @alignOf(Position)), pos_array.meta.stride);
    try testing.expectEqual(@as(usize, 0), pos_array.capacity);
    try testing.expectEqual(@as(usize, 0), pos_array.len);
}

test "ComponentArray from type with value" {
    const allocator = std.testing.allocator;
    var array = try ComponentArray.from(allocator, Position{
        .x = 1.0,
        .y = 2.0,
    });
    defer array.deinit();

    try testing.expectEqual(componentId(Position), array.meta.id);
    try testing.expectEqual(@sizeOf(Position), array.meta.size);
    try testing.expectEqual(@alignOf(Position), array.meta.alignment);
    try testing.expectEqual(@as(usize, 1), array.len);
    try testing.expectEqual(@as(usize, ComponentArray.min_occupied_capacity), array.capacity);

    // Verify the appended value
    const pos = array.get(0, Position).?;
    try testing.expectEqual(@as(f32, 1.0), pos.x);
    try testing.expectEqual(@as(f32, 2.0), pos.y);
}

test "ComponentArray zero-sized type handling" {
    const allocator = testing.allocator;

    var empty_array = createMarkerArray(allocator);
    defer empty_array.deinit();

    try testing.expectEqual(@as(usize, 0), empty_array.meta.size);
    try testing.expectEqual(@as(usize, 0), empty_array.meta.stride);
}

test "ComponentArray append and get operations" {
    const allocator = testing.allocator;
    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    const positions = [_]Position{
        .{ .x = 1.0, .y = 2.0 },
        .{ .x = 3.0, .y = 4.0 },
        .{ .x = 5.0, .y = 6.0 },
    };

    // Append positions
    for (positions) |pos| {
        try pos_array.append(pos);
    }

    try testing.expectEqual(@as(usize, 3), pos_array.len);
    try testing.expect(pos_array.capacity >= 3);

    // Get and verify positions
    for (positions, 0..) |expected, i| {
        const actual = pos_array.get(i, Position).?;
        try testing.expectEqual(expected.x, actual.x);
        try testing.expectEqual(expected.y, actual.y);
    }

    // Test out of bounds
    try testing.expect(pos_array.get(3, Position) == null);
    try testing.expect(pos_array.get(100, Position) == null);
}

test "ComponentArray set operation and type safety" {
    const allocator = testing.allocator;
    var health_array = createHealthArray(allocator);
    defer health_array.deinit();

    try health_array.append(Health{ .current = 100, .max = 100 });
    try health_array.append(Health{ .current = 50, .max = 80 });

    // Valid set operation
    try health_array.set(0, Health{ .current = 90, .max = 100 });
    const updated = health_array.get(0, Health).?;
    try testing.expectEqual(@as(i32, 90), updated.current);

    // Test bounds checking
    try testing.expectError(error.IndexOutOfBounds, health_array.set(2, Health{ .current = 0, .max = 0 }));
    try testing.expectError(error.IndexOutOfBounds, health_array.set(100, Health{ .current = 0, .max = 0 }));
}

test "ComponentArray insert operation" {
    const allocator = testing.allocator;
    const initial_positions = [_]Position{
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 3.0, .y = 3.0 },
    };

    var pos_array = try createPopulatedArray(allocator, Position, &initial_positions);
    defer pos_array.deinit();

    // Insert at beginning
    try pos_array.insert(0, Position{ .x = 0.0, .y = 0.0 });
    try testing.expectEqual(@as(usize, 3), pos_array.len);
    try testing.expectEqual(@as(f32, 0.0), pos_array.get(0, Position).?.x);
    try testing.expectEqual(@as(f32, 1.0), pos_array.get(1, Position).?.x);

    // Insert in middle
    try pos_array.insert(2, Position{ .x = 2.0, .y = 2.0 });
    try testing.expectEqual(@as(usize, 4), pos_array.len);
    try testing.expectEqual(@as(f32, 2.0), pos_array.get(2, Position).?.x);
    try testing.expectEqual(@as(f32, 3.0), pos_array.get(3, Position).?.x);

    // Insert at end
    try pos_array.insert(4, Position{ .x = 4.0, .y = 4.0 });
    try testing.expectEqual(@as(usize, 5), pos_array.len);
    try testing.expectEqual(@as(f32, 4.0), pos_array.get(4, Position).?.x);

    // Test out of bounds
    try testing.expectError(error.IndexOutOfBounds, pos_array.insert(6, Position{ .x = 0.0, .y = 0.0 }));
}

test "ComponentArray shiftRemove operation" {
    const allocator = testing.allocator;
    const initial_positions = [_]Position{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 2.0, .y = 2.0 },
        .{ .x = 3.0, .y = 3.0 },
    };

    var pos_array = try createPopulatedArray(allocator, Position, &initial_positions);
    defer pos_array.deinit();

    // Remove from middle
    pos_array.shiftRemove(1);
    try testing.expectEqual(@as(usize, 3), pos_array.len);
    try testing.expectEqual(@as(f32, 0.0), pos_array.get(0, Position).?.x);
    try testing.expectEqual(@as(f32, 2.0), pos_array.get(1, Position).?.x);
    try testing.expectEqual(@as(f32, 3.0), pos_array.get(2, Position).?.x);

    // Remove from beginning
    pos_array.shiftRemove(0);
    try testing.expectEqual(@as(usize, 2), pos_array.len);
    try testing.expectEqual(@as(f32, 2.0), pos_array.get(0, Position).?.x);

    // Remove from end
    pos_array.shiftRemove(1);
    try testing.expectEqual(@as(usize, 1), pos_array.len);
    try testing.expectEqual(@as(f32, 2.0), pos_array.get(0, Position).?.x);

    // Remove out of bounds (should be safe)
    pos_array.shiftRemove(10);
    try testing.expectEqual(@as(usize, 1), pos_array.len);
}

test "ComponentArray swapRemove operation" {
    const allocator = testing.allocator;
    const initial_positions = [_]Position{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 2.0, .y = 2.0 },
        .{ .x = 3.0, .y = 3.0 },
    };

    var pos_array = try createPopulatedArray(allocator, Position, &initial_positions);
    defer pos_array.deinit();

    // Swap remove from middle - should move last element to removed position
    pos_array.swapRemove(1);
    try testing.expectEqual(@as(usize, 3), pos_array.len);
    try testing.expectEqual(@as(f32, 0.0), pos_array.get(0, Position).?.x);
    try testing.expectEqual(@as(f32, 3.0), pos_array.get(1, Position).?.x); // Last element moved here
    try testing.expectEqual(@as(f32, 2.0), pos_array.get(2, Position).?.x);

    // Swap remove last element - should just decrement length
    pos_array.swapRemove(2);
    try testing.expectEqual(@as(usize, 2), pos_array.len);

    // Swap remove out of bounds (should be safe)
    pos_array.swapRemove(10);
    try testing.expectEqual(@as(usize, 2), pos_array.len);
}

test "ComponentArray capacity management" {
    const allocator = testing.allocator;
    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    // Test ensureCapacity
    try pos_array.ensureCapacity(10);
    try testing.expectEqual(@as(usize, 10), pos_array.capacity);

    // Ensuring smaller capacity should not change it
    try pos_array.ensureCapacity(5);
    try testing.expectEqual(@as(usize, 10), pos_array.capacity);

    // Test ensureTotalCapacity with growth
    try pos_array.ensureTotalCapacity(25);
    try testing.expect(pos_array.capacity >= 25);

    // Fill up to test automatic growth
    var pos_array2 = createPositionArray(allocator);
    defer pos_array2.deinit();

    for (0..20) |i| {
        try pos_array2.append(Position{ .x = @floatFromInt(i), .y = @floatFromInt(i) });
    }
    try testing.expectEqual(@as(usize, 20), pos_array2.len);
    try testing.expect(pos_array2.capacity >= 20);
}

test "ComponentArray clearRetainingCapacity" {
    const allocator = testing.allocator;
    const positions = [_]Position{
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 2.0, .y = 2.0 },
        .{ .x = 3.0, .y = 3.0 },
    };

    var pos_array = try createPopulatedArray(allocator, Position, &positions);
    defer pos_array.deinit();

    const original_capacity = pos_array.capacity;
    pos_array.clearRetainingCapacity();

    try testing.expectEqual(@as(usize, 0), pos_array.len);
    try testing.expectEqual(original_capacity, pos_array.capacity);

    // Should be able to append after clearing
    try pos_array.append(Position{ .x = 10.0, .y = 10.0 });
    try testing.expectEqual(@as(usize, 1), pos_array.len);
}

test "ComponentArray shrinkAndFree" {
    const allocator = testing.allocator;
    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    // Build up capacity
    try pos_array.ensureCapacity(100);
    for (0..10) |i| {
        try pos_array.append(Position{ .x = @floatFromInt(i), .y = @floatFromInt(i) });
    }

    try testing.expectEqual(@as(usize, 100), pos_array.capacity);
    try testing.expectEqual(@as(usize, 10), pos_array.len);

    // Shrink to fit current length
    try pos_array.shrinkAndFree(10);
    try testing.expectEqual(@as(usize, 10), pos_array.capacity);
    try testing.expectEqual(@as(usize, 10), pos_array.len);

    // Verify data is still intact
    for (0..10) |i| {
        const pos = pos_array.get(i, Position).?;
        try testing.expectEqual(@as(f32, @floatFromInt(i)), pos.x);
    }

    // Shrink to zero when empty
    pos_array.clearRetainingCapacity();
    try pos_array.shrinkAndFree(0);
    try testing.expectEqual(@as(usize, 0), pos_array.capacity);
    try testing.expectEqual(@as(usize, 0), pos_array.len);
}

test "ComponentArray zero-sized component operations" {
    const allocator = testing.allocator;
    var empty_array = createMarkerArray(allocator);
    defer empty_array.deinit();

    // Zero-sized types should handle operations gracefully
    try empty_array.append(Marker{});
    try empty_array.append(Marker{});

    try testing.expectEqual(@as(usize, 2), empty_array.len);

    // Get should return null for zero-sized types
    try testing.expect(empty_array.get(0, Marker) == null);
    try testing.expect(empty_array.get(1, Marker) == null);

    empty_array.swapRemove(0);
    try testing.expectEqual(@as(usize, 1), empty_array.len);
}

test "ComponentArray large component handling" {
    const allocator = testing.allocator;
    var large_array = ComponentArray.initFromType(
        allocator,
        componentId(LargeComponent),
        @sizeOf(LargeComponent),
        @alignOf(LargeComponent),
    );
    defer large_array.deinit();

    var large_comp = LargeComponent{};
    large_comp.data[0] = 0xAA;
    large_comp.data[1023] = 0xBB;
    large_comp.id = 12345;

    try large_array.append(large_comp);

    const retrieved = large_array.get(0, LargeComponent).?;
    try testing.expectEqual(@as(u8, 0xAA), retrieved.data[0]);
    try testing.expectEqual(@as(u8, 0xBB), retrieved.data[1023]);
    try testing.expectEqual(@as(u64, 12345), retrieved.id);
}

test "ComponentArray memory alignment correctness" {
    const allocator = testing.allocator;

    // Test with types that have different alignment requirements
    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    try pos_array.append(TestPositions.basic);
    try pos_array.append(TestPositions.alternative);

    // Verify that pointers are properly aligned
    const ptr1 = pos_array.get(0, Position).?;
    const ptr2 = pos_array.get(1, Position).?;

    try testing.expect(@intFromPtr(ptr1) % @alignOf(Position) == 0);
    try testing.expect(@intFromPtr(ptr2) % @alignOf(Position) == 0);

    // Verify stride calculation includes alignment
    try testing.expect(pos_array.meta.stride >= @sizeOf(Position));
    try testing.expect(pos_array.meta.stride % @alignOf(Position) == 0);
}

test "ComponentArray stress test with many operations" {
    const allocator = testing.allocator;
    var pos_array = createPositionArray(allocator);
    defer pos_array.deinit();

    // Add many elements
    for (0..1000) |i| {
        try pos_array.append(Position{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2) });
    }

    try testing.expectEqual(@as(usize, 1000), pos_array.len);

    // Remove every other element using swapRemove
    var i: usize = 0;
    while (i < pos_array.len) {
        pos_array.swapRemove(i);
        i += 1; // Skip the element that moved into position i
    }

    try testing.expectEqual(@as(usize, 500), pos_array.len);

    // Insert elements back
    for (0..250) |idx| {
        try pos_array.insert(idx * 2, Position{ .x = @floatFromInt(idx + 2000), .y = @floatFromInt(idx + 3000) });
    }

    try testing.expectEqual(@as(usize, 750), pos_array.len);
}
