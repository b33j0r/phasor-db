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
    // Deinit all archetype values before freeing the map storage
    var it = self.archetypes.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.archetypes.deinit(self.allocator);
    self.entities.deinit(self.allocator);
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
    var new_set = try ComponentSet.fromComponents(self.allocator, components);
    defer new_set.deinit();

    // Create union of existing and new components
    var union_set = try existing_set.setUnion(&new_set);
    defer union_set.deinit();

    // Calculate new archetype ID
    const new_archetype_id = union_set.calculateId();

    // TODO: this is incorrect, we want to replace the component values here
    if (new_archetype_id == src_archetype_id) {
        return; // Entity already has these components
    }

    // Get or create the new archetype
    var new_archetype = self.archetypes.getPtr(new_archetype_id);
    if (new_archetype == null) {
        // Create new archetype from the union set
        const archetype = try Archetype.fromComponentSet(self.allocator, &union_set);
        try self.archetypes.put(self.allocator, new_archetype_id, archetype);
        new_archetype = self.archetypes.getPtr(new_archetype_id);
    }

    // Move entity data from source archetype to destination archetype
    const src_row_index = entity.row_index;
    
    // Add entity ID to new archetype first
    try new_archetype.?.entity_ids.append(self.allocator, entity_id);
    const new_entity_index = new_archetype.?.entity_ids.items.len - 1;
    
    // Copy existing component data to matching columns in new archetype
    // We need to copy raw bytes since we don't know the component types at runtime
    // Get fresh pointer to source archetype after hashmap operations
    const src_archetype_fresh = self.archetypes.getPtr(src_archetype_id).?;
    for (src_archetype_fresh.columns) |*src_column| {
        // Find matching column in new archetype
        for (new_archetype.?.columns) |*dest_column| {
            if (dest_column.meta.id == src_column.meta.id) {
                // Copy raw bytes from source to destination
                const src_offset = src_row_index * src_column.meta.stride;
                const src_data = src_column.buffer.data[src_offset .. src_offset + src_column.meta.size];
                
                // Ensure destination has capacity
                try dest_column.ensureTotalCapacity(dest_column.len + 1);
                const dst_offset = dest_column.len * dest_column.meta.stride;
                @memcpy(dest_column.buffer.data[dst_offset .. dst_offset + dest_column.meta.size], src_data);
                dest_column.len += 1;
                break;
            }
        }
    }
    
    // Add new component data to new archetype
    const fields = std.meta.fields(@TypeOf(components));
    inline for (fields) |field| {
        const component_value = @field(components, field.name);
        const ComponentType = @TypeOf(component_value);
        const comp_id = root.componentId(ComponentType);
        
        // Check if this component is actually new (not already in the source archetype)
        var is_new_component = true;
        for (src_archetype_fresh.columns) |src_column| {
            if (src_column.meta.id == comp_id) {
                is_new_component = false;
                break;
            }
        }
        
        // Only append if it's a truly new component
        if (is_new_component) {
            // Find the column for this component in the new archetype
            for (new_archetype.?.columns) |*column| {
                if (column.meta.id == comp_id) {
                    try column.append(component_value);
                    break;
                }
            }
        }
    }
    
    // Remove entity from source archetype
    _ = try src_archetype_fresh.removeEntityByIndex(src_row_index);

    // If a swap occurred, update the moved entity's row_index bookkeeping
    if (src_row_index < src_archetype_fresh.entity_ids.items.len) {
        const moved_id = src_archetype_fresh.entity_ids.items[src_row_index];
        if (self.entities.get(moved_id)) |moved_entity| {
            var me = moved_entity;
            me.row_index = src_row_index;
            try self.entities.put(self.allocator, moved_id, me);
        }
    }
    
    // Clean up source archetype if it's now empty
    self.pruneIfEmpty(src_archetype_fresh);
    
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
    var remove_set = try ComponentSet.fromComponents(self.allocator, components);
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
    var new_archetype = self.archetypes.getPtr(new_archetype_id);
    if (new_archetype == null) {
        // Create new archetype from the difference set
        const archetype = try Archetype.fromComponentSet(self.allocator, &diff_set);
        try self.archetypes.put(self.allocator, new_archetype_id, archetype);
        new_archetype = self.archetypes.getPtr(new_archetype_id);
    }

    // Move entity data from source archetype to destination archetype
    const src_row_index = entity.row_index;
    
    // Add entity ID to new archetype first
    try new_archetype.?.entity_ids.append(self.allocator, entity_id);
    const new_entity_index = new_archetype.?.entity_ids.items.len - 1;
    
    // Copy existing component data to matching columns in new archetype
    // Only copy components that are NOT being removed
    // Get fresh pointer to source archetype after hashmap operations
    const src_archetype_fresh = self.archetypes.getPtr(src_archetype_id).?;
    for (src_archetype_fresh.columns) |*src_column| {
        // Check if this component should be kept (exists in diff_set)
        var should_keep = false;
        for (diff_set.items.items) |meta| {
            if (meta.id == src_column.meta.id) {
                should_keep = true;
                break;
            }
        }
        
        if (should_keep) {
            // Find matching column in new archetype
            for (new_archetype.?.columns) |*dest_column| {
                if (dest_column.meta.id == src_column.meta.id) {
                    // Copy raw bytes from source to destination
                    const src_offset = src_row_index * src_column.meta.stride;
                    const src_data = src_column.buffer.data[src_offset .. src_offset + src_column.meta.size];
                    
                    // Ensure destination has capacity
                    try dest_column.ensureTotalCapacity(dest_column.len + 1);
                    const dst_offset = dest_column.len * dest_column.meta.stride;
                    @memcpy(dest_column.buffer.data[dst_offset .. dst_offset + dest_column.meta.size], src_data);
                    dest_column.len += 1;
                    break;
                }
            }
        }
    }
    
    // Remove entity from source archetype
    _ = try src_archetype_fresh.removeEntityByIndex(src_row_index);

    // If a swap occurred, update the moved entity's row_index bookkeeping
    if (src_row_index < src_archetype_fresh.entity_ids.items.len) {
        const moved_id = src_archetype_fresh.entity_ids.items[src_row_index];
        if (self.entities.get(moved_id)) |moved_entity| {
            var me = moved_entity;
            me.row_index = src_row_index;
            try self.entities.put(self.allocator, moved_id, me);
        }
    }
    
    // Clean up source archetype if it's now empty
    self.pruneIfEmpty(src_archetype_fresh);
    
    // Update entity record
    var updated_entity = entity;
    updated_entity.archetype_id = new_archetype_id;
    updated_entity.row_index = new_entity_index;
    try self.entities.put(self.allocator, entity_id, updated_entity);
}