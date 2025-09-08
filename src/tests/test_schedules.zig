const std = @import("std");

const Database = root.Database;
const Entity = root.Entity;
const Mut = root.Mut;
const Query = root.Query;
const Schedule = root.Schedule;
const System = root.System;
const Transaction = root.Transaction;
const Without = root.Without;
const Res = root.Res;
const root = @import("../root.zig");

const fixtures = @import("fixtures.zig");
const Health = fixtures.Health;
const Player = fixtures.Player;

test "System with no params is an error" {
    const system_with_no_params_fn = struct {
        pub fn system_with_no_params() !void {}
    }.system_with_no_params;

    const allocator = std.testing.allocator;

    var db = Database.init(allocator);
    defer db.deinit();

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    schedule.add(system_with_no_params_fn) catch {
        // expect to fail because system has no parameters
        return;
    };
    try std.testing.expect(false);
}

test "System with transaction system param" {
    const system_with_tx_param_fn = struct {
        pub fn system_with_tx_param(tx: *Transaction) !void {
            // Add an entity to the transaction
            _ = try tx.createEntity(.{Player{}});
        }
    }.system_with_tx_param;

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    try schedule.add(system_with_tx_param_fn);
    try schedule.run(&tx);

    try tx.execute();

    var query_result = try db.query(.{Player});
    defer query_result.deinit();
    try std.testing.expect(query_result.count() == 1);
}

test "System with Res(T) param" {
    // Use Health as a resource for this test
    const system_with_res_param_fn = struct {
        pub fn system_with_res_param(res: Res(Health)) !void {
            // Modify the resource
            res.ptr.current += 10;
        }
    }.system_with_res_param;

    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.insertResource(Health{ .current = 93, .max = 100 });

    var schedule = Schedule.init(allocator);
    defer schedule.deinit();

    var tx = db.transaction();
    defer tx.deinit();

    try schedule.add(system_with_res_param_fn);
    try schedule.run(&tx);

    try tx.execute();

    const health_res = db.getResource(Health) orelse unreachable;
    try std.testing.expect(health_res.current == 103);
}
