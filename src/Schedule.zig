allocator: std.mem.Allocator,
systems: std.ArrayListUnmanaged(System) = .empty,

const std = @import("std");
const root = @import("root.zig");
const System = root.System;
const Database = root.Database;
const Transaction = root.Transaction;

const Schedule = @This();

pub fn init(allocator: std.mem.Allocator) Schedule {
    return Schedule{
        .allocator = allocator,
        .systems = .empty,
    };
}

pub fn deinit(self: *Schedule) void {
    self.systems.deinit(self.allocator);
}

pub fn add(self: *Schedule, comptime system_fn: anytype) !void {
    const system = try System.from(system_fn);
    try self.systems.append(self.allocator, system);
}

pub fn run(self: *const Schedule, tx: *Transaction) !void {
    for (self.systems.items) |system| {
        try system.run(tx);
    }
}
