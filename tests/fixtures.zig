const std = @import("std");

const root = @import("phasor-db");
const componentId = root.componentId;
const ComponentId = root.ComponentId;
const ComponentArray = root.ComponentArray;
const Entity = root.Entity;
const Archetype = root.Archetype;

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const Velocity = struct {
    dx: f32,
    dy: f32,
};

pub const Health = struct {
    current: i32,
    max: i32,
};

pub const Moveable = struct {
    pos: Position,
    vel: Velocity,
};

pub const Marker = struct {};

pub const Player = struct {};

pub const LargeComponent = struct {
    data: [1024]u8 = [_]u8{0} ** 1024,
    id: u64 = 42,
};

// Common test data constants for consistent testing
pub const TestPositions = struct {
    pub const origin = Position{ .x = 0.0, .y = 0.0 };
    pub const basic = Position{ .x = 1.0, .y = 2.0 };
    pub const alternative = Position{ .x = 3.0, .y = 4.0 };
    pub const third = Position{ .x = 5.0, .y = 6.0 };
};

pub const TestHealth = struct {
    pub const full = Health{ .current = 100, .max = 100 };
    pub const damaged = Health{ .current = 50, .max = 100 };
    pub const critical = Health{ .current = 10, .max = 100 };
    pub const high_max = Health{ .current = 150, .max = 200 };
    pub const very_high = Health{ .current = 250, .max = 300 };
};

pub const TestVelocity = struct {
    pub const stationary = Velocity{ .dx = 0.0, .dy = 0.0 };
    pub const moving_right = Velocity{ .dx = 0.5, .dy = -0.5 };
    pub const moving_left = Velocity{ .dx = -1.0, .dy = 1.5 };
};

// Test entity configurations for common scenarios
pub const TestEntity = struct {
    pub const basic_positioned = .{ .position = TestPositions.basic };
    pub const healthy_positioned = .{ .position = TestPositions.basic, .health = TestHealth.full };
    pub const moving_entity = .{ .position = TestPositions.basic, .velocity = TestVelocity.moving_right };
    pub const full_entity = .{ .position = TestPositions.basic, .health = TestHealth.full, .velocity = TestVelocity.moving_right };
};

/// Helper function for creating test arrays
pub fn createPositionArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.initFromType(allocator, componentId(Position), @sizeOf(Position), @alignOf(Position), null, null);
}

/// Helper function for creating test arrays
pub fn createHealthArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.initFromType(allocator, componentId(Health), @sizeOf(Health), @alignOf(Health), null, null);
}

/// Helper function for creating test arrays
pub fn createMarkerArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.initFromType(allocator, componentId(Marker), @sizeOf(Marker), @alignOf(Marker), null, null);
}

/// Test fixture for creating and populating arrays
pub fn createPopulatedArray(allocator: std.mem.Allocator, comptime T: type, items: []const T) !ComponentArray {
    var array = ComponentArray.initFromType(allocator, componentId(T), @sizeOf(T), @alignOf(T), null, null);

    for (items) |item| {
        try array.append(item);
    }

    return array;
}

pub fn archetypeFromComponents(
    allocator: std.mem.Allocator,
    comptime components: anytype,
) !Archetype {
    // Create a ComponentSet from the components (which captures traits in ComponentMeta)
    var component_set = try root.ComponentSet.fromComponents(allocator, components);
    defer component_set.deinit();

    // Delegate to fromComponentSet - this is now the single source of truth
    return Archetype.fromComponentSet(allocator, &component_set);
}
