const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Query = root.Query;
const ComponentId = root.ComponentId;
const ResourceManager = root.ResourceManager;

allocator: std.mem.Allocator,
database: *Database,
commands: std.ArrayListUnmanaged(Command) = .empty,
has_executed: bool = false,

const Transaction = @This();

const Command = struct {
    context: *anyopaque,
    execute: *const fn (ctx: *anyopaque, db: *Database) anyerror!void,
    cleanup: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn init(allocator: std.mem.Allocator, database: *Database) Transaction {
    return Transaction{
        .allocator = allocator,
        .database = database,
    };
}

pub fn deinit(self: *Transaction) void {
    // Only clean up remaining command contexts if execute() hasn't been called
    if (!self.has_executed) {
        for (self.commands.items) |command| {
            command.cleanup(command.context, self.allocator);
        }
    }
    self.commands.deinit(self.allocator);
}

pub fn execute(self: *Transaction) !void {
    if (self.has_executed) {
        return error.TransactionAlreadyExecuted;
    }
    for (self.commands.items) |command| {
        try command.execute(command.context, self.database);
        // Clean up the allocated context after execution
        command.cleanup(command.context, self.allocator);
    }
    self.commands.clearRetainingCapacity();
    self.has_executed = true;
}

//
// Facade commands: passthrough to db immediately
//

pub fn getEntity(self: *Transaction, entity_id: Entity.Id) ?Entity {
    return self.database.getEntity(entity_id);
}

pub fn query(self: *Transaction, components: anytype) !Query {
    return self.database.query(components);
}

pub fn groupBy(self: *Transaction, component_id: ComponentId, key: i32) !*const root.Group {
    return self.database.groupBy(component_id, key);
}

pub fn getResource(self: *Transaction, comptime T: type) ?*T {
    return self.database.getResource(T);
}

pub fn hasResource(self: *Transaction, comptime T: type) bool {
    return self.database.hasResource(T);
}

pub fn insertResource(self: *Transaction, resource: anytype) !void {
    self.database.insertResource(resource);
}

pub fn removeResource(self: *Transaction, comptime T: type) !void {
    self.database.removeResource(T);
}

//
// Deferred commands: queued to be executed later
//

pub fn createEntity(self: *Transaction, components: anytype) !Entity.Id {
    // We will make explicit use of Database.reserveEntityId and Database.createEntityWithId
    // so that the caller still gets an Entity.Id, but the command can be deferred.
    const entity_id = self.database.reserveEntityId();

    // Create a context that captures the entity_id and components for deferred execution
    const CreateEntityContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        fn execute(ctx: *anyopaque, db: *Database) anyerror!void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            _ = try db.createEntityWithId(self_ctx.entity_id, self_ctx.components);
        }

        fn cleanup(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            allocator.destroy(self_ctx);
        }
    };

    const context = try self.allocator.create(CreateEntityContext);
    context.* = CreateEntityContext{
        .entity_id = entity_id,
        .components = components,
    };

    const command = Command{
        .context = context,
        .execute = CreateEntityContext.execute,
        .cleanup = CreateEntityContext.cleanup,
    };

    try self.commands.append(self.allocator, command);
    return entity_id;
}

pub fn removeEntity(self: *Transaction, entity_id: Entity.Id) !void {
    // Create a context that captures the entity_id for deferred execution
    const RemoveEntityContext = struct {
        entity_id: Entity.Id,

        fn execute(ctx: *anyopaque, db: *Database) anyerror!void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            try db.removeEntity(self_ctx.entity_id);
        }

        fn cleanup(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            allocator.destroy(self_ctx);
        }
    };

    const context = try self.allocator.create(RemoveEntityContext);
    context.* = RemoveEntityContext{
        .entity_id = entity_id,
    };

    const command = Command{
        .context = context,
        .execute = RemoveEntityContext.execute,
        .cleanup = RemoveEntityContext.cleanup,
    };

    try self.commands.append(self.allocator, command);
}

pub fn addComponents(self: *Transaction, entity_id: Entity.Id, components: anytype) !void {
    // Create a context that captures the entity_id and components for deferred execution
    const AddComponentsContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        fn execute(ctx: *anyopaque, db: *Database) anyerror!void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            try db.addComponents(self_ctx.entity_id, self_ctx.components);
        }

        fn cleanup(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            allocator.destroy(self_ctx);
        }
    };

    const context = try self.allocator.create(AddComponentsContext);
    context.* = AddComponentsContext{
        .entity_id = entity_id,
        .components = components,
    };

    const command = Command{
        .context = context,
        .execute = AddComponentsContext.execute,
        .cleanup = AddComponentsContext.cleanup,
    };

    try self.commands.append(self.allocator, command);
}

pub fn removeComponents(self: *Transaction, entity_id: Entity.Id, components: anytype) !void {
    // Create a context that captures the entity_id and components for deferred execution
    const RemoveComponentsContext = struct {
        entity_id: Entity.Id,
        components: @TypeOf(components),

        fn execute(ctx: *anyopaque, db: *Database) anyerror!void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            try db.removeComponents(self_ctx.entity_id, self_ctx.components);
        }

        fn cleanup(ctx: *anyopaque, allocator: std.mem.Allocator) void {
            const self_ctx = @as(*@This(), @ptrCast(@alignCast(ctx)));
            allocator.destroy(self_ctx);
        }
    };

    const context = try self.allocator.create(RemoveComponentsContext);
    context.* = RemoveComponentsContext{
        .entity_id = entity_id,
        .components = components,
    };

    const command = Command{
        .context = context,
        .execute = RemoveComponentsContext.execute,
        .cleanup = RemoveComponentsContext.cleanup,
    };

    try self.commands.append(self.allocator, command);
}
