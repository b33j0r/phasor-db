//! `Archetype` represents a collection of entities that share the same set of components.
//! It holds the actual column data that entities are stored in.

const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const ComponentArray = root.ComponentArray;
const Entity = root.Entity;
const componentId = root.componentId;

allocator: std.mem.Allocator,
id: Archetype.Id,
name: []const ComponentId,
columns: []ComponentArray,
entity_ids: std.ArrayListUnmanaged(Entity.Id),

pub const Archetype = @This();
pub const Id = u64;

pub fn fromComponentSet(
    allocator: std.mem.Allocator,
    component_set: *const root.ComponentSet,
) !Archetype {
    const len = component_set.len();
    if (len == 0) {
        return error.EmptyComponentSet;
    }

    // Allocate arrays for component IDs and columns
    const component_ids = try allocator.alloc(ComponentId, len);
    const columns = try allocator.alloc(ComponentArray, len);

    // The ComponentSet is already sorted, so we can iterate directly
    for (component_set.items.items, 0..) |meta, i| {
        component_ids[i] = meta.id;
        columns[i] = ComponentArray.initFromType(
            allocator,
            meta.id,
            meta.size,
            meta.alignment,
            meta.trait,
            meta.drop,
        );
    }

    const archetype_id = component_set.calculateId();

    return Archetype.init(allocator, archetype_id, component_ids, columns);
}

pub fn init(
    allocator: std.mem.Allocator,
    id: Id,
    name: []const ComponentId,
    columns: []ComponentArray,
) Archetype {
    return Archetype{
        .allocator = allocator,
        .id = id,
        .name = name,
        .columns = columns,
        .entity_ids = .empty,
    };
}

pub fn deinit(self: *Archetype) void {
    // Free the component columns
    for (self.columns) |*column| {
        column.deinit();
    }

    // Free the arrays
    self.allocator.free(self.name);
    self.allocator.free(self.columns);

    // Free entity_ids if it has allocated memory
    self.entity_ids.deinit(self.allocator);
}

pub fn getColumn(
    self: *const Archetype,
    component_id: ComponentId,
) ?*const ComponentArray {
    for (self.columns) |*column| {
        if (column.meta.id == component_id) {
            return column;
        }
        if (column.meta.trait) |trait| {
            if (trait.id == component_id) {
                return column;
            }
        }
    }
    return null;
}

pub fn getColumnMut(
    self: *Archetype,
    component_id: ComponentId,
) ?*ComponentArray {
    for (self.columns) |*column| {
        if (column.meta.id == component_id) {
            return column;
        }
    }
    return null;
}

pub fn getColumnIndexById(
    self: *const Archetype,
    component_id: ComponentId,
) ?usize {
    for (self.columns, 0..) |column, index| {
        if (column.meta.id == component_id) {
            return index;
        }
    }
    return null;
}

pub fn getColumnIndexByType(
    self: *const Archetype,
    comptime T: type,
) ?usize {
    const target_id = componentId(T);
    return self.getColumnIndexById(target_id);
}

fn getSortedComponentIds(components: anytype) [std.meta.fields(@TypeOf(components)).len]ComponentId {
    const fields = std.meta.fields(@TypeOf(components));

    comptime var component_ids: [fields.len]ComponentId = undefined;
    comptime {
        for (fields, 0..) |field, i| {
            const component_value = @field(components, field.name);
            const ComponentType = @TypeOf(component_value);
            component_ids[i] = componentId(ComponentType);
        }
        std.mem.sort(ComponentId, &component_ids, {}, struct {
            fn lt(_: void, a: ComponentId, b: ComponentId) bool {
                return a < b;
            }
        }.lt);
    }

    return component_ids;
}

// Sorted component IDs from the tuple TYPE (not the value)
fn getSortedComponentIdsFromType(comptime TupleT: type) [std.meta.fields(TupleT).len]ComponentId {
    const fields = std.meta.fields(TupleT);
    comptime var ids: [fields.len]ComponentId = undefined;

    inline for (fields, 0..) |fld, i| {
        ids[i] = componentId(fld.type);
    }

    // Sort deterministically at comptime
    comptime std.sort.pdq(ComponentId, &ids, {}, std.sort.asc(ComponentId));
    return ids;
}

// Archetype id derived purely from the component tuple type
pub fn idFromType(comptime TupleT: type) Id {
    const ids = comptime getSortedComponentIdsFromType(TupleT);
    var hasher = std.hash.XxHash64.init(0);
    inline for (ids) |id| {
        hasher.update(std.mem.asBytes(&id));
    }
    return hasher.final();
}

pub fn calculateId(comptime components: anytype) Id {
    const sorted_ids = comptime getSortedComponentIds(components);

    var hasher = std.hash.Wyhash.init(0);
    inline for (sorted_ids) |comp_id| {
        hasher.update(std.mem.asBytes(&comp_id));
    }
    return hasher.final();
}

/// Adds an entity to the archetype with the provided components.
/// Returns the index of the entity in the archetype's entity list.
pub fn addEntity(
    self: *Archetype,
    entity_id: Entity.Id,
    components: anytype,
) !usize {
    @setEvalBranchQuota(10000);
    const fields = std.meta.fields(@TypeOf(components));

    // Verify the number of columns matches
    if (fields.len != self.columns.len) {
        return error.ComponentCountMismatch;
    }

    // Get sorted component IDs from the input
    const input_sorted_ids = comptime getSortedComponentIdsFromType(@TypeOf(components));

    // Verify that the component types match exactly
    for (input_sorted_ids, self.name) |input_id, archetype_id| {
        if (input_id != archetype_id) {
            return error.ComponentTypeMismatch;
        }
    }

    // Add the entity ID to our entity list
    try self.entity_ids.append(self.allocator, entity_id);
    const entity_index = self.entity_ids.items.len - 1;

    // Add component data to each column in the correct order
    inline for (input_sorted_ids, 0..) |target_id, column_index| {
        // Find the matching field in the components struct
        inline for (fields) |field| {
            const component_value = @field(components, field.name);
            const ComponentType = @TypeOf(component_value);

            if (componentId(ComponentType) == target_id) {
                try self.columns[column_index].append(component_value);
                break;
            }
        }
    }

    return entity_index;
}

pub fn removeEntityByIndex(
    self: *Archetype,
    entity_index: usize,
) !Entity.Id {
    if (entity_index >= self.entity_ids.items.len) {
        return error.IndexOutOfBounds;
    }

    // Remove the entity ID from the list
    const entity_id = self.entity_ids.swapRemove(entity_index);

    // Remove component data from each column
    for (self.columns) |*column| {
        column.swapRemove(entity_index);
    }

    return entity_id;
}

pub fn hasComponents(
    self: *const Archetype,
    components: []const ComponentId,
) bool {
    for (components) |comp_id| {
        if (self.getColumn(comp_id) == null) {
            return false;
        }
    }
    return true;
}

pub fn hasAnyComponents(
    self: *const Archetype,
    components: []const ComponentId,
) bool {
    for (components) |comp_id| {
        if (self.getColumn(comp_id) != null) {
            return true;
        }
    }
    return false;
}

/// Copies an entity from this archetype to another archetype.
/// Only copies components that exist in both archetypes.
/// Returns the new entity index in the destination archetype.
pub fn copyEntityTo(
    self: *Archetype,
    entity_index: usize,
    dest_archetype: *Archetype,
) !usize {
    if (entity_index >= self.entity_ids.items.len) {
        return error.IndexOutOfBounds;
    }

    const entity_id = self.entity_ids.items[entity_index];

    // Add entity ID to destination archetype first
    try dest_archetype.entity_ids.append(dest_archetype.allocator, entity_id);
    const new_entity_index = dest_archetype.entity_ids.items.len - 1;

    // Copy component data for matching components between archetypes
    for (self.columns) |*src_column| {
        // Find matching column in destination archetype
        for (dest_archetype.columns) |*dest_column| {
            if (dest_column.meta.id == src_column.meta.id) {
                try src_column.copyElementToEnd(entity_index, dest_column);
                break;
            }
        }
    }

    return new_entity_index;
}
