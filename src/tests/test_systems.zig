const std = @import("std");
const root = @import("../root.zig");
const fixtures = @import("fixtures.zig");
const Allocator = std.mem.Allocator;
const Database = root.Database;
const Query = root.Query;
const QueryResult = root.QueryResult;
const System = root.System;
const Transaction = root.Transaction;
const Entity = root.Entity;
const testing = std.testing;

const DeltaTime = struct {
    seconds: f32,
};

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

// pub fn velocitySystem(tx: Transaction, q: Q(.{ Position, Velocity }), dt: Res(DeltaTime)) void {}
//
// pub fn Q(spec: anytype) type {
//     return Query;
// }
//
// pub fn Res(comptime T: type) type {
//     return T;
// }

test "System define" {
    const allocator = testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();

    const entity = try db.createEntity(.{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 1 },
    });

    // Define the velocity system
    const VelocitySystem = System(struct {
        pub fn run(_: Transaction, q: QueryResult, dt: DeltaTime) void {
            var it = q.iterator();
            while (it.next()) |e| {
                const pos = e.get(Position).?;
                const vel = e.get(Velocity).?;

                pos.*.x += vel.*.x * dt.seconds;
                pos.*.y += vel.*.y * dt.seconds;
            }
        }
    });

    var transaction = db.transaction();
    defer transaction.deinit();

    const dt = DeltaTime{ .seconds = 1.0 };

    var query = try db.query(.{ Position, Velocity });
    defer query.deinit();

    VelocitySystem.run(transaction, query, dt);
    try transaction.execute();

    const updated_entity = db.getEntity(entity).?;
    const updated_pos = updated_entity.get(Position).?;

    try testing.expect(updated_pos.*.x == 1.0);
    try testing.expect(updated_pos.*.y == 1.0);
}
