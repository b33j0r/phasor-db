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

pub fn removeEntity(self: *Database, entity_id: Entity.Id) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;

    std.debug.assert(entity.id == entity_id, "Entity ID mismatch");

    // Get the archetype and row index for this entity
    const archetype = self.archetypes.get(entity.archetype_id) orelse return error.ArchetypeNotFound;

    // Remove the entity from the archetype
    try archetype.removeEntity(self.allocator, entity.row_index, entity_id);
}

// fn moveEntity(
//     db: *Database,
//     src: *Archetype, dst: *Archetype,
//     src_row: usize,
//     entity_id: Entity.Id,
// ) !usize { // returns dst_row
//     // For each column in dst, find matching column in src (by ComponentId).
//     // Copy present components; init or skip others.
//     // Push entity_id into dst.entity_ids, swap-remove from src.
//     // Return dst row for location update.
// }
