# `phasor-db`

The `phasor-db` library is an Entity-Component-System database. For a more complete ECS library, see [phasor](https://github.com/b33j0r/phasor), which uses this as a dependency.

## Architecture

- [x] `ComponentArray` is a type-erased array of components.
- [X] `Archetype` is a table of entity data, consisting of a `ComponentArray` for each column type.
- [X] `Database` is a collection of `Archetype`s.
- [X] `Entity` is a view into a row in an `Archetype`, providing access to its components.
- [X] `query` allows for efficient retrieval of entities with specific components.

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
}
```
