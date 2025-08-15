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

pub fn createEntity(self: *Database, components: anytype) !Entity.Id {
    const entity_id = self.next_entity_id;
    self.next_entity_id += 1;

    const archetype_id = Archetype.calculateId(components);

    // Get or create the archetype for this combination of components
    var archetype = self.archetypes.getPtr(archetype_id);
    if (archetype == null) {
        // Create new archetype if it doesn't exist
        const new_archetype = try Archetype.fromComponents(self.allocator, components);
        try self.archetypes.put(self.allocator, archetype_id, new_archetype);
        archetype = self.archetypes.getPtr(archetype_id);
    }

    // Add the entity to the archetype's entity list and component data
    const entity_index = try archetype.?.addEntity(entity_id, components);

    // Create and store the Entity record that tracks which archetype and row this entity is in
    const entity = Entity{
        .id = entity_id,
        .archetype_id = archetype_id,
        .index = entity_index,  // Row index within the archetype
    };

    try self.entities.put(self.allocator, entity_id, entity);

    return entity_id;
}

pub fn getEntity(self: *Database, id: Entity.Id) ?Entity {
    return self.entities.get(id);
}