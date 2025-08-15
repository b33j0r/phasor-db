const std = @import("std");
const root = @import("../root.zig");
const componentId = root.componentId;
const ComponentId = root.ComponentId;
const ComponentArray = root.ComponentArray;
const Entity = root.Entity;

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

pub const Marker = struct {};

pub const LargeComponent = struct {
    data: [1024]u8 = [_]u8{0} ** 1024,
    id: u64 = 42,
};

/// Helper function for creating test arrays
pub fn createPositionArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.init(
        allocator,
        componentId(Position),
        @sizeOf(Position),
        @alignOf(Position),
    );
}

/// Helper function for creating test arrays
pub fn createHealthArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.init(
        allocator,
        componentId(Health),
        @sizeOf(Health),
        @alignOf(Health),
    );
}

/// Helper function for creating test arrays
pub fn createMarkerArray(allocator: std.mem.Allocator) ComponentArray {
    return ComponentArray.init(
        allocator,
        componentId(Marker),
        @sizeOf(Marker),
        @alignOf(Marker),
    );
}

/// Test fixture for creating and populating arrays
pub fn createPopulatedArray(allocator: std.mem.Allocator, comptime T: type, items: []const T) !ComponentArray {
    var array = ComponentArray.init(
        allocator,
        componentId(T),
        @sizeOf(T),
        @alignOf(T),
    );

    for (items) |item| {
        try array.append(item);
    }

    return array;
}