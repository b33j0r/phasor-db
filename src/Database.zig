const std = @import("std");
const root = @import("root.zig");
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentSet = root.ComponentSet;
const ComponentMeta = root.ComponentMeta;

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

pub fn getEntity(self: *Database, id: Entity.Id) ?Entity {
    return self.entities.get(id);
}

pub fn removeEntity(self: *Database, entity_id: Entity.Id) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;

    std.debug.assert(entity.id == entity_id, "Entity ID mismatch");

    // Get the archetype and row index for this entity
    const archetype = self.archetypes.getPtr(entity.archetype_id) orelse return error.ArchetypeNotFound;

    // Remove the entity from the archetype
    _ = try archetype.removeEntityByIndex(entity.index);
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
        .database = self,
        .archetype_id = archetype_id,
        .row_index = entity_index,  // Row index within the archetype
    };

    try self.entities.put(self.allocator, entity_id, entity);

    return entity_id;
}

pub fn addComponents(
    self: *Database,
    entity_id: Entity.Id,
    components: anytype,
) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;
    const src_archetype = self.archetypes.getPtr(entity.archetype_id).?;

    // Create ComponentSet from existing archetype components
    var existing_set = ComponentSet.init(self.allocator);
    defer existing_set.deinit();
    
    for (src_archetype.columns) |column| {
        try existing_set.insertSorted(column.meta);
    }

    // Create ComponentSet from new components to add
    const new_set = try ComponentSet.fromComponents(self.allocator, components);
    defer new_set.deinit();

    // Create union of existing and new components
    const union_set = try existing_set.setUnion(&new_set);
    defer union_set.deinit();

    // Calculate new archetype ID
    const new_archetype_id = union_set.calculateId();

    // If the new archetype is the same as the current one, no need to move
    if (new_archetype_id == entity.archetype_id) {
        return; // Entity already has these components
    }

    // Get or create the new archetype
    const new_archetype = self.archetypes.getPtr(new_archetype_id);
    if (new_archetype == null) {
        // TODO: Need to implement Archetype.fromComponentSet
        // For now, return an error
        return error.ArchetypeCreationNotImplemented;
    }

    // TODO: Move entity data from source archetype to destination archetype
    // This requires copying component data and updating entity record
    return error.EntityMoveNotImplemented;
}