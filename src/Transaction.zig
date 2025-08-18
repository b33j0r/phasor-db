const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;

allocator: std.mem.Allocator,
database: *Database,
commands: std.ArrayListUnmanaged(Command) = .empty,

const Transaction = @This();

const Command = struct {
    context: *anyopaque,
    execute: *const fn (ctx: *anyopaque, db: *Database) anyerror!void,
};

pub fn init(allocator: std.mem.Allocator, database: *Database) Transaction {
    return Transaction{
        .allocator = allocator,
        .database = database,
    };
}

pub fn deinit(self: *Transaction) void {
    self.commands.deinit(self.allocator);
}

pub fn execute(self: *Transaction) !void {
    for (self.commands.items) |command| {
        try command.execute(command.context, self.database);
    }
    self.commands.clear();
}

pub fn createEntity(self: *Transaction, components: anytype) !Entity.Id {
    // ...
}

pub fn removeEntity(self: *Transaction, entity_id: Entity.Id) !void {
    // ...
}

pub fn addComponents(self: *Transaction, entity_id: Entity.Id, components: anytype) !void {
    // ...
}

pub fn removeComponents(self: *Transaction, entity_id: Entity.Id, components: anytype) !void {
    // ...
}
