# `phasor-db`

The `phasor-db` library is an Entity-Component-System database. For a more complete ECS library, see [phasor](https://github.com/b33j0r/phasor), which uses this as a dependency.

## Architecture

- `ComponentArray` is a type-erased array of components.
- `Archetype` is a table of entity data, consisting of a `ComponentArray` for each column type.
- `Database` is a collection of `Archetype`s.
- `Entity` is a view into a row in an `Archetype`, providing access to its components.
- `Query` allows for efficient retrieval of entities with specific components.

## Usage

```zig
const std = @import("std");
const ecs = @import("phasor-db");

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = ecs.Database.init(allocator);
    defer db.deinit();

    const entity = try db.createEntity(.{
        Position{ .x = 0.0, .y = 0.0 },
        Velocity{ .x = 1.0, .y = 1.0 },
    });

    const readEntity = db.getEntity(entity).?;
    const position = readEntity.get(Position).?;
    const velocity = readEntity.get(Velocity).?;

    std.debug.print("Entity Position: ({}, {})\n", .{ position.x, position.y });
    std.debug.print("Entity Velocity: ({}, {})\n", .{ velocity.x, velocity.y });

    // Add another entity
    _ = try db.createEntity(.{
        Position{ .x = 10.0, .y = 10.0 },
        Velocity{ .x = 2.0, .y = 2.0 },
    });

    // Query all entities with Position and Velocity components
    var query = try db.query(.{Position, Velocity});
    defer query.deinit();

    var iterator = query.iterator();
    while (iterator.next()) |matched_entity| {
        const pos = matched_entity.get(Position).?;
        const vel = matched_entity.get(Velocity).?;
        std.debug.print("Queried Entity Position: ({}, {})\n", .{ pos.x, pos.y });
        std.debug.print("Queried Entity Velocity: ({}, {})\n", .{ vel.x, vel.y });
    }

}
```
