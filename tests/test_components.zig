const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
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

test "componentId functionality" {
    // IDs should be consistent for same type
    try testing.expectEqual(componentId(Position), componentId(Position));

    // IDs should be unique across different types
    const pos_id = componentId(Position);
    const health_id = componentId(Health);
    const marker_id = componentId(Marker);
    try testing.expect(pos_id != health_id);
    try testing.expect(health_id != marker_id);
    try testing.expect(pos_id != marker_id);

    // Values and types should generate same ID
    try testing.expectEqual(componentId(TestPositions.basic), componentId(Position));
    try testing.expectEqual(componentId(TestHealth.high_max), componentId(Health));
}

test "ComponentMeta from - trait with identical layout" {
    const Superclass = struct {
        id: u64,
    };
    const Subclass = struct {
        id: u64,
        pub const __trait__ = Superclass;
    };
    const meta = root.ComponentMeta.from(Subclass);
    try testing.expectEqual(componentId(Superclass), meta.trait.?.id);
    try testing.expectEqual(root.Trait.Kind.IdenticalLayout, meta.trait.?.kind);
}

test "ComponentMeta from - trait with marker" {
    const MarkerTrait = struct {
        pub const __trait__ = struct {};
    };
    const meta = root.ComponentMeta.from(MarkerTrait);
    try testing.expectEqual(root.Trait.Kind.Marker, meta.trait.?.kind);
}

test "ComponentMeta from - trait with grouped" {
    const GroupedTrait = struct {
        pub const __group_key__ = 42;
        // We don't care what the trait is, but this is required to make
        // ComponentMeta.from notice the group key. TODO?
        pub const __trait__ = struct {};
    };
    const meta = root.ComponentMeta.from(GroupedTrait);
    switch (meta.trait.?.kind) {
        .Grouped => |grouped| {
            try testing.expectEqual(42, grouped.group_key);
        },
        else => try testing.expect(false),
    }
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

test "ComponentArray removal operations" {
    const allocator = testing.allocator;

    // Test shiftRemove - maintains order
    const shift_positions = [_]Position{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 2.0, .y = 2.0 },
    };
    var shift_array = try createPopulatedArray(allocator, Position, &shift_positions);
    defer shift_array.deinit();

    shift_array.shiftRemove(1); // Remove middle element
    try testing.expectEqual(@as(usize, 2), shift_array.len);
    try testing.expectEqual(@as(f32, 0.0), shift_array.get(0, Position).?.x);
    try testing.expectEqual(@as(f32, 2.0), shift_array.get(1, Position).?.x); // Order preserved

    // Test swapRemove - faster but doesn't preserve order
    const swap_positions = [_]Position{
        .{ .x = 10.0, .y = 10.0 },
        .{ .x = 11.0, .y = 11.0 },
        .{ .x = 12.0, .y = 12.0 },
    };
    var swap_array = try createPopulatedArray(allocator, Position, &swap_positions);
    defer swap_array.deinit();

    swap_array.swapRemove(1); // Remove middle element
    try testing.expectEqual(@as(usize, 2), swap_array.len);
    try testing.expectEqual(@as(f32, 10.0), swap_array.get(0, Position).?.x);
    try testing.expectEqual(@as(f32, 12.0), swap_array.get(1, Position).?.x); // Last element moved to position 1
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

test "ComponentArray.set drops previous element" {
    const allocator = std.testing.allocator;

    const OwnedCounter = struct { count: usize };
    const Droppable = struct {
        counter: *OwnedCounter,
        const Self = @This();
        pub fn deinit(self: *Self) void {
            self.counter.count += 1;
        }
    };

    var c = OwnedCounter{ .count = 0 };
    var arr = root.ComponentArray.initFromType(allocator, root.componentId(Droppable), @sizeOf(Droppable), @alignOf(Droppable), null, root.Drop.maybeFrom(Droppable));
    defer arr.deinit();

    try arr.append(Droppable{ .counter = &c });
    try arr.set(0, Droppable{ .counter = &c });
    try testing.expectEqual(@as(usize, 1), c.count);
}

test "ComponentArray.deinit drops all elements" {
    const allocator = std.testing.allocator;

    const OwnedCounter = struct { count: usize };
    const Droppable = struct {
        counter: *OwnedCounter,
        const Self = @This();
        pub fn deinit(self: *Self) void {
            self.counter.count += 1;
        }
    };

    var c = OwnedCounter{ .count = 0 };
    var arr = root.ComponentArray.initFromType(allocator, root.componentId(Droppable), @sizeOf(Droppable), @alignOf(Droppable), null, root.Drop.maybeFrom(Droppable));
    try arr.append(Droppable{ .counter = &c });
    try arr.append(Droppable{ .counter = &c });

    arr.deinit();
    try testing.expectEqual(@as(usize, 2), c.count);
}
