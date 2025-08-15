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

test "Archetype create empty" {
    const allocator = std.testing.allocator;
    var array = try ComponentArray.from(allocator, Position{
        .x = 1.0,
        .y = 2.0,
    });
    defer array.deinit();
}
