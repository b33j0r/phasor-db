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
    for (self.columns) |column| {
        if (column.id == component_id) {
            return &column;
        }
    }
    return null;
}

pub fn getColumnIndexById(
    self: *const Archetype,
    component_id: ComponentId,
) ?usize {
    for (self.columns, 0..) |column, index| {
        if (column.id == component_id) {
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

fn getSortedComponentIds(comptime components: anytype) [std.meta.fields(@TypeOf(components)).len]ComponentId {
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

pub fn calculateId(comptime components: anytype) Id {
    const sorted_ids = comptime getSortedComponentIds(components);

    var hasher = std.hash.Wyhash.init(0);
    inline for (sorted_ids) |comp_id| {
        hasher.update(std.mem.asBytes(&comp_id));
    }
    return hasher.final();
}

pub fn fromComponents(
    allocator: std.mem.Allocator,
    comptime components: anytype,
) !Archetype {
    const fields = std.meta.fields(@TypeOf(components));
    const sorted_ids = comptime getSortedComponentIds(components);

    // Create arrays in the same sorted order
    var component_ids: [fields.len]ComponentId = undefined;
    var columns: [fields.len]ComponentArray = undefined;

    // Find the field for each sorted component ID and create the column
    inline for (sorted_ids, 0..) |target_id, i| {
        inline for (fields) |field| {
            const component_value = @field(components, field.name);
            const ComponentType = @TypeOf(component_value);
            if (componentId(ComponentType) == target_id) {
                component_ids[i] = target_id;
                columns[i] = ComponentArray.init(
                    allocator,
                    target_id,
                    @sizeOf(ComponentType),
                    @alignOf(ComponentType),
                );
                break;
            }
        }
    }

    const archetype_id = calculateId(components);
    const name = try allocator.dupe(ComponentId, &component_ids);
    const columns_slice = try allocator.dupe(ComponentArray, &columns);

    return Archetype.init(allocator, archetype_id, name, columns_slice);
}

pub fn addEntity(
    self: *Archetype,
    entity_id: Entity.Id,
    components: anytype,
) !usize {
    const fields = std.meta.fields(@TypeOf(components));

    // Verify the number of columns matches
    if (fields.len != self.columns.len) {
        return error.ComponentCountMismatch;
    }

    // Get sorted component IDs from the input
    const input_sorted_ids = comptime getSortedComponentIds(components);

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
