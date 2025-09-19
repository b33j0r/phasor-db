//! `Database` is the primary user interface for the `phasor-db` library.
//! It stores entity-component data in archetype tables. This is abstracted
//! behind the `createEntity`, `getEntity`, `removeEntity`, `addComponents`,
//! `removeComponents`, and `query` methods.
const std = @import("std");
const root = @import("root.zig");
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentSet = root.ComponentSet;
const ComponentMeta = root.ComponentMeta;
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const QuerySpec = root.QuerySpec;
const QueryResult = root.QueryResult;
const GroupByResult = root.GroupByResult;

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
    var it = self.archetypes.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.archetypes.deinit(self.allocator);
    self.entities.deinit(self.allocator);
}

pub fn getEntityCount(self: *const Database) usize {
    return self.entities.count();
}

pub fn getArchetypeCount(self: *const Database) usize {
    return self.archetypes.count();
}

pub fn getEntity(self: *Database, id: Entity.Id) ?Entity {
    return self.entities.get(id);
}

pub fn removeEntity(self: *Database, entity_id: Entity.Id) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;

    std.debug.assert(entity.id == entity_id);

    // Get the archetype and row index for this entity
    const archetype = self.archetypes.getPtr(entity.archetype_id) orelse return error.ArchetypeNotFound;

    // Check if there's an entity that will be moved due to swapRemove
    var moved_entity_id: ?Entity.Id = null;
    if (entity.row_index < archetype.entity_ids.items.len - 1) {
        // The last entity will be moved to this position
        moved_entity_id = archetype.entity_ids.items[archetype.entity_ids.items.len - 1];
    }

    // Remove the entity from the archetype
    _ = try archetype.removeEntityByIndex(entity.row_index);

    // Update the row index of the entity that was moved (if any)
    if (moved_entity_id) |moved_id| {
        if (self.entities.getPtr(moved_id)) |moved_entity_ptr| {
            moved_entity_ptr.row_index = entity.row_index;
        }
    }

    // Remove the entity from the entities map
    _ = self.entities.swapRemove(entity_id);

    // Clean up empty archetypes
    self.pruneIfEmpty(archetype);
}

pub fn reserveEntityId(self: *Database) Entity.Id {
    const entity_id = self.next_entity_id;
    self.next_entity_id += 1;
    return entity_id;
}

pub fn createEntity(self: *Database, components: anytype) !Entity.Id {
    const entity_id = self.reserveEntityId();
    return try self.createEntityWithId(entity_id, components);
}

pub fn createEntityWithId(self: *Database, entity_id: Entity.Id, components: anytype) !Entity.Id {
    var component_set = try ComponentSet.fromComponentsRuntime(self.allocator, components);
    defer component_set.deinit();

    const archetype_id = component_set.calculateId();

    // Get or create the archetype for this combination of components
    const archetype = try self.getOrCreateArchetype(archetype_id, &component_set);

    // Add the entity to the archetype's entity list and component data
    const entity_index = try archetype.addEntity(entity_id, components);

    // Create and store the Entity record
    const entity = Entity{
        .id = entity_id,
        .database = self,
        .archetype_id = archetype_id,
        .row_index = entity_index,
    };

    try self.entities.put(self.allocator, entity_id, entity);

    return entity_id;
}

/// Creates a new archetype from a ComponentSet and publishes the ArchetypeAdded event.
fn createArchetype(self: *Database, component_set: *const ComponentSet) !Archetype {
    return try Archetype.fromComponentSet(self.allocator, component_set);
}

/// Gets an existing archetype or creates a new one if it doesn't exist.
fn getOrCreateArchetype(self: *Database, archetype_id: Archetype.Id, component_set: *const ComponentSet) !*Archetype {
    // Check if archetype already exists
    if (self.archetypes.getPtr(archetype_id)) |existing_archetype| {
        return existing_archetype;
    }

    // Create new archetype using createArchetype
    const new_archetype = try self.createArchetype(component_set);
    try self.archetypes.put(self.allocator, archetype_id, new_archetype);

    // Return pointer to the newly stored archetype
    return self.archetypes.getPtr(archetype_id).?;
}

/// Removes an archetype from the database if it has no entities.
/// Uses asserts to ensure the archetype is truly empty before removal.
fn pruneIfEmpty(self: *Database, archetype: *Archetype) void {
    // Check if archetype is empty
    if (archetype.entity_ids.items.len == 0) {
        // Assert that all columns are also empty
        for (archetype.columns) |column| {
            std.debug.assert(column.len == 0);
        }

        // Find the archetype key to remove (safer than iterator + modification)
        var key_to_remove: ?Archetype.Id = null;
        var iterator = self.archetypes.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.id == archetype.id) {
                key_to_remove = entry.key_ptr.*;
                break;
            }
        }

        // Remove the archetype if found
        if (key_to_remove) |key| {
            // Get the archetype to deinitialize it
            if (self.archetypes.getPtr(key)) |arch_to_remove| {
                arch_to_remove.deinit();
            }
            // Now safely remove from the map
            _ = self.archetypes.swapRemove(key);
        }
    }
}

pub fn addComponents(
    self: *Database,
    entity_id: Entity.Id,
    components: anytype,
) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;
    const src_archetype_id = entity.archetype_id;

    // Create ComponentSet from existing archetype components
    var existing_set = ComponentSet.init(self.allocator);
    defer existing_set.deinit();

    // Get fresh pointer to avoid invalidation issues
    const src_archetype = self.archetypes.getPtr(src_archetype_id).?;
    for (src_archetype.columns) |column| {
        try existing_set.insertSorted(column.meta);
    }

    // Create ComponentSet from new components to add
    var new_set = try ComponentSet.fromComponentsRuntime(self.allocator, components);
    defer new_set.deinit();

    // Create union of existing and new components
    var union_set = try existing_set.setUnion(&new_set);
    defer union_set.deinit();

    // Calculate new archetype ID
    const new_archetype_id = union_set.calculateId();

    // Handle the case where the archetype doesn't change (updating existing components only)
    if (new_archetype_id == src_archetype_id) {
        // Update component values in-place in the same archetype
        const fields = std.meta.fields(@TypeOf(components));
        inline for (fields) |field| {
            const component_value = @field(components, field.name);
            const ComponentType = @TypeOf(component_value);
            const comp_id = root.componentId(ComponentType);

            // Find the column for this component in the current archetype
            for (src_archetype.columns) |*column| {
                if (column.meta.id == comp_id) {
                    try column.set(entity.row_index, component_value);
                    break;
                }
            }
        }
        return; // Done updating components in-place
    }

    // Get or create the new archetype
    const new_archetype = try self.getOrCreateArchetype(new_archetype_id, &union_set);

    // Move entity data from source archetype to destination archetype
    const src_row_index = entity.row_index;

    // Get fresh pointer to source archetype after hashmap operations
    const src_archetype_fresh = self.archetypes.getPtr(src_archetype_id).?;

    // Use the proper abstraction to copy entity between archetypes
    const new_entity_index = try src_archetype_fresh.copyEntityTo(src_row_index, new_archetype);

    // Remove entity from source archetype and handle bookkeeping
    _ = try src_archetype_fresh.removeEntityByIndex(src_row_index);

    // If a swap occurred during removal, update the moved entity's row_index bookkeeping
    if (src_row_index < src_archetype_fresh.entity_ids.items.len) {
        const moved_id = src_archetype_fresh.entity_ids.items[src_row_index];
        if (self.entities.getPtr(moved_id)) |moved_entity_ptr| {
            moved_entity_ptr.row_index = src_row_index;
        }
    }

    // Add/update component data in the new archetype
    const fields = std.meta.fields(@TypeOf(components));
    inline for (fields) |field| {
        const component_value = @field(components, field.name);
        const ComponentType = @TypeOf(component_value);
        const comp_id = root.componentId(ComponentType);

        // Check if this component already exists in the source archetype
        var component_exists_in_source = false;
        for (src_archetype_fresh.columns) |src_column| {
            if (src_column.meta.id == comp_id) {
                component_exists_in_source = true;
                break;
            }
        }

        // Find the column for this component in the new archetype
        for (new_archetype.columns) |*column| {
            if (column.meta.id == comp_id) {
                if (component_exists_in_source) {
                    // Component already exists, update it at the entity's index
                    try column.set(new_entity_index, component_value);
                } else {
                    // New component, append it
                    try column.append(component_value);
                }
                break;
            }
        }
    }

    // Note: moveEntityTo() already removed the entity from source archetype and handled bookkeeping
    // Get fresh pointer to source archetype for cleanup check
    const src_archetype_for_cleanup = self.archetypes.getPtr(src_archetype_id).?;

    // Clean up source archetype if it's now empty
    self.pruneIfEmpty(src_archetype_for_cleanup);

    // Update entity record
    var updated_entity = entity;
    updated_entity.archetype_id = new_archetype_id;
    updated_entity.row_index = new_entity_index;
    try self.entities.put(self.allocator, entity_id, updated_entity);
}

pub fn removeComponents(
    self: *Database,
    entity_id: Entity.Id,
    components: anytype,
) !void {
    const entity = self.entities.get(entity_id) orelse return error.EntityNotFound;
    const src_archetype_id = entity.archetype_id;

    // Create ComponentSet from existing archetype components
    var existing_set = ComponentSet.init(self.allocator);
    defer existing_set.deinit();

    // Get fresh pointer to avoid invalidation issues
    const src_archetype = self.archetypes.getPtr(src_archetype_id).?;
    for (src_archetype.columns) |column| {
        try existing_set.insertSorted(column.meta);
    }

    // Create ComponentSet from components to remove
    var remove_set = try ComponentSet.fromComponentsRuntime(self.allocator, components);
    defer remove_set.deinit();

    // Create difference: existing components minus components to remove
    var diff_set = try existing_set.setDifference(&remove_set);
    defer diff_set.deinit();

    // If the resulting set is empty, we can't have an entity with no components
    if (diff_set.len() == 0) {
        return error.CannotRemoveAllComponents;
    }

    // Calculate new archetype ID
    const new_archetype_id = diff_set.calculateId();

    // If the new archetype is the same as the current one, nothing to remove
    if (new_archetype_id == src_archetype_id) {
        return; // Entity doesn't have these components to remove
    }

    // Get or create the new archetype
    const new_archetype = try self.getOrCreateArchetype(new_archetype_id, &diff_set);

    // Move entity data from source archetype to destination archetype
    const src_row_index = entity.row_index;

    // Get fresh pointer to source archetype after hashmap operations
    const src_archetype_fresh = self.archetypes.getPtr(src_archetype_id).?;

    // Use the proper abstraction to copy entity between archetypes
    const new_entity_index = try src_archetype_fresh.copyEntityTo(src_row_index, new_archetype);

    // Remove entity from source archetype and handle bookkeeping
    _ = try src_archetype_fresh.removeEntityByIndex(src_row_index);

    // If a swap occurred during removal, update the moved entity's row_index bookkeeping
    if (src_row_index < src_archetype_fresh.entity_ids.items.len) {
        const moved_id = src_archetype_fresh.entity_ids.items[src_row_index];
        if (self.entities.getPtr(moved_id)) |moved_entity_ptr| {
            moved_entity_ptr.row_index = src_row_index;
        }
    }

    // Get fresh pointer to source archetype for cleanup check
    const src_archetype_for_cleanup = self.archetypes.getPtr(src_archetype_id).?;

    // Clean up source archetype if it's now empty
    self.pruneIfEmpty(src_archetype_for_cleanup);

    // Update entity record
    var updated_entity = entity;
    updated_entity.archetype_id = new_archetype_id;
    updated_entity.row_index = new_entity_index;
    try self.entities.put(self.allocator, entity_id, updated_entity);
}

pub fn addComponent(
    self: *Database,
    entity_id: Entity.Id,
    component: anytype,
) !void {
    return try self.addComponents(entity_id, .{component});
}

pub fn removeComponent(
    self: *Database,
    entity_id: Entity.Id,
    component_type: type,
) !void {
    const dummy = @as(component_type, undefined);
    return try self.removeComponents(entity_id, .{dummy});
}

/// Queries the database for archetypes that match the specified component types.
pub fn query(self: *Database, spec: anytype) !QueryResult {
    var q = try QuerySpec.fromComponentTypes(self.allocator, spec);
    defer q.deinit();
    return try q.execute(self);
}

test query {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const Position = struct {
        x: f32,
        y: f32,
    };

    // Create some entities with different components
    _ = try db.createEntity(.{
        Position{ .x = 1.0, .y = 2.0 },
    });
    _ = try db.createEntity(.{
        Position{ .x = 3.0, .y = 4.0 },
    });

    // QuerySpec for entities with position component
    var q = try db.query(.{Position});
    defer q.deinit();

    try std.testing.expectEqual(2, q.count());

    // Iterate through the results
    var it = q.iterator();
    while (it.next()) |entity| {
        std.log.debug("Found entity: {}\n", .{entity.id});
    }
}

/// Queries the database for groups within a trait
pub fn groupBy(self: *Database, TraitT: type) !GroupByResult {
    return GroupByResult.fromTraitType(self.allocator, self, TraitT);
}

test groupBy {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    const Types = struct {
        pub const Data = struct {
            number: i32,
        };

        pub fn Layer(N: i32) type {
            return struct {
                pub const __group_key__ = N;
                pub const __trait__ = LayerN;
            };
        }

        pub const LayerN = struct {};
    };

    const Layer = Types.Layer;
    const LayerN = Types.LayerN;

    // Create some entities with different layers
    _ = try db.createEntity(.{
        Layer(1){},
        Types.Data{ .number = 10 },
    });
    _ = try db.createEntity(.{
        Layer(2){},
        Types.Data{ .number = 20 },
    });
    _ = try db.createEntity(.{
        Layer(1){},
        Types.Data{ .number = 30 },
    });

    // QuerySpec for groups by Layer trait
    var group_by = try db.groupBy(LayerN);
    defer group_by.deinit();

    try std.testing.expectEqual(2, group_by.count());

    // Check the groups
    var it = group_by.iterator();
    const layer_1_group = it.next().?;
    const layer_2_group = it.next().?;
    try std.testing.expectEqual(null, it.next()); // No more groups

    // Check Layer 1 group
    var layer_1_group_it = layer_1_group.iterator();
    const layer_1_entity_1 = layer_1_group_it.next().?;
    const layer_1_entity_2 = layer_1_group_it.next().?;
    try std.testing.expectEqual(null, layer_1_group_it.next()); // No more entities

    // Check Layer 2 group
    var layer_2_group_it = layer_2_group.iterator();
    const layer_2_entity = layer_2_group_it.next().?;
    try std.testing.expectEqual(null, layer_2_group_it.next()); // No more entities

    // Verify entities in Layer 1
    try std.testing.expectEqual(10, layer_1_entity_1.get(Types.Data).?.number);
    try std.testing.expectEqual(30, layer_1_entity_2.get(Types.Data).?.number);

    // Verify entity in Layer 2
    try std.testing.expectEqual(20, layer_2_entity.get(Types.Data).?.number);
}
