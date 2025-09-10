
![phasor-logo.png](docs/phasor-logo.png)

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


## Key Features

- Archetype-based ECS storage with component columns and contiguous entity rows.
- Query by component types or trait types (virtual components). QueryResult supports iterator(), count(), first(), and deinit().
- Trait system:
  - Marker traits (zero-sized) match presence.
  - Identical-layout traits expose a view type identical to the component for ergonomic access.
  - Grouped traits with __group_key__ enable grouping entities by a key.
- Grouping APIs:
  - Database.groupBy(TraitType) groups all entities by a grouped trait.
  - QueryResult.groupBy(TraitType) groups only the matched subset.
  - GroupByResult.Group supports iterator(), query(.{...}), and nested groupBy.
- Resource manager (db.resources) for process-wide typed resources: insert/get/has/remove.
- Transactions for batching entity create/remove and component add/remove with deferred execution.
- Simple component access via Entity.get(T), Entity.has(T), and mutation via Entity.set(value).
- Zig 0.14+ compatible (see build.zig.zon minimum_zig_version).

## Additional Examples

### Using count and first on query results
```zig
const std = @import("std");
const ecs = @import("phasor-db");
const Database = ecs.Database;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    _ = try db.createEntity(.{ Position{ .x = 0, .y = 0 }, Velocity{ .dx = 1, .dy = 1 } });
    _ = try db.createEntity(.{ Position{ .x = 10, .y = 10 }, Velocity{ .dx = -1, .dy = 0 } });

    var q = try db.query(.{Position, Velocity});
    defer q.deinit();

    const first = q.first();
    std.debug.print("count={}, first?={}\n", .{ q.count(), first != null });
}
```

### Trait-based queries (identical layout)
```zig
const ecs = @import("phasor-db");
const Database = ecs.Database;

const ComponentTypeFactory = struct {
    pub fn Component(N: i32) type {
        return struct {
            n: i32 = N,
            pub const __trait__ = ComponentX; // identical layout
        };
    }
    pub const ComponentX = struct { n: i32 };
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const C1 = ComponentTypeFactory.Component(1);
    const C2 = ComponentTypeFactory.Component(2);
    _ = try db.createEntity(.{C1{}});
    _ = try db.createEntity(.{C2{}});

    var q = try db.query(.{ComponentTypeFactory.ComponentX});
    defer q.deinit();

    var it = q.iterator();
    while (it.next()) |e| {
        const x = e.get(ComponentTypeFactory.ComponentX).?; // identical-layout trait view
        std.debug.print("n={}\n", .{x.n});
    }
}
```

### Grouping by a grouped trait
```zig
const ecs = @import("phasor-db");
const Database = ecs.Database;

const Types = struct {
    pub fn Layer(N: i32) type {
        return struct {
            pub const __group_key__ = N;
            pub const __trait__ = LayerN; // grouped trait
        };
    }
    pub const LayerN = struct {};
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const Layer = Types.Layer;
    _ = try db.createEntity(.{ Layer(1){} });
    _ = try db.createEntity(.{ Layer(2){} });
    _ = try db.createEntity(.{ Layer(1){} });

    var groups = try db.groupBy(Types.LayerN);
    defer groups.deinit();

    var git = groups.iterator();
    while (git.next()) |group| {
        // Iterate entities in this group
        var eit = group.iterator();
        while (eit.next()) |e| {
            _ = e; // use entity or subquery via group.query(.{...})
        }
    }
}
```

### Resources
```zig
const ecs = @import("phasor-db");
const Database = ecs.Database;

const ClearColor = struct { r: f32, g: f32, b: f32, a: f32 };

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.resources.insert(ClearColor{ .r = 0.1, .g = 0.2, .b = 0.3, .a = 1.0 });
    const cc = db.resources.get(ClearColor).?;
    std.debug.print("clear=({}, {}, {}, {})\n", .{ cc.r, cc.g, cc.b, cc.a });
}
```

### Transactions
```zig
const ecs = @import("phasor-db");
const Database = ecs.Database;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var txn = db.transaction();
    defer txn.deinit();

    const id = try txn.createEntity(.{ Position{ .x = 0, .y = 0 } });
    try txn.addComponents(id, .{ Velocity{ .dx = 1, .dy = 1 } });

    // Immediate reads/queries are available via the transaction
    var q = try txn.query(.{Position});
    defer q.deinit();
    std.debug.print("visible_before_execute={}\n", .{ q.count() });

    try txn.execute(); // apply deferred operations to the database
}
```