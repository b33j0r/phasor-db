const std = @import("std");
const root = @import("src/root.zig");
const Database = root.Database;
const Transaction = root.Transaction;

// Simple test components (matching fixtures pattern)
const Position = struct {
    x: f32,
    y: f32,
};

const TestEntity = struct {
    const basic_positioned = .{ .position = Position{ .x = 1.0, .y = 2.0 } };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Starting double-free reproduction test...", .{});

    var db = Database.init(allocator);
    defer db.deinit();

    std.log.info("Creating transaction...", .{});
    var txn = db.transaction();
    defer txn.deinit(); // This should cause the double-free

    std.log.info("Adding commands to transaction...", .{});
    // Add a command that allocates context
    _ = try txn.createEntity(TestEntity.basic_positioned);
    
    std.log.info("Executing transaction...", .{});
    try txn.execute(); // This will cleanup contexts and set has_executed = true
    
    std.log.info("Transaction executed successfully", .{});
    std.log.info("About to call deinit() via defer - this should cause double-free...", .{});
    
    // When this function exits, the defer txn.deinit() will be called
    // This should trigger the double-free bug since execute() already cleaned up contexts
}