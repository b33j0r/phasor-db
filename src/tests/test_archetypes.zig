const std = @import("std");
const testing = std.testing;

const root = @import("../root.zig");
const ComponentArray = root.ComponentArray;
const componentId = root.componentId;

const Archetype = root.Archetype;

const fixtures = @import("fixtures.zig");
const Position = fixtures.Position;
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