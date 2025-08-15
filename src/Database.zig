const std = @import("std");
const root = @import("root.zig");
const Entity = root.Entity;
const Archetype = root.Archetype;

allocator: std.mem.Allocator,
archetypes: std.AutoArrayHashMapUnmanaged(Archetype.Id, Archetype) = .empty,
entities: std.AutoArrayHashMapUnmanaged(Entity.Id, Entity) = .empty,
next_entity_id: Entity.Id = 0,

const Database = @This();

pub fn init(allocator: std.mem.Allocator) Database {
    return Database{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Database) void {
    self.archetypes.deinit(self.allocator);
    self.entities.deinit(self.allocator);
}

pub fn createEntity(self: *Database, components: anytype) Entity.Id {
    _ = components;

    const entity_id = self.next_entity_id;
    self.next_entity_id += 1;

    return entity_id;
}

pub fn getEntity(self: *Database, id: Entity.Id) ?Entity {
    return self.entities.get(id);
}