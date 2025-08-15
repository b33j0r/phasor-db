const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const ComponentArray = root.ComponentArray;
const Entity = root.Entity;
const componentId = root.componentId;

id: Archetype.Id,
name: []const ComponentId,
columns: []ComponentArray,
entity_ids: std.ArrayListUnmanaged(Entity.Id),

pub const Archetype = @This();
pub const Id = u64;

pub fn init(
    id: Id,
    name: []const ComponentId,
    columns: []ComponentArray,
) Archetype {
    return Archetype{
        .id = id,
        .name = name,
        .columns = columns,
        .entity_ids = .empty,
    };
}

pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
    // Free the component columns
    for (self.columns) |*column| {
        column.deinit();
    }

    // Free the arrays
    allocator.free(self.name);
    allocator.free(self.columns);

    // Free entity_ids if it has allocated memory
    self.entity_ids.deinit(allocator);
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

pub fn calculateId(
    comptime components: anytype,
) Id {
    var hasher = std.hash.Wyhash.init(0);
    inline for (components) |component| {
        const component_type = if (@TypeOf(component) == type) component else @TypeOf(component);
        hasher.update(@typeName(component_type));
    }
    return hasher.final();
}
pub fn fromComponents(
    allocator: std.mem.Allocator,
    comptime components: anytype,
) !Archetype {
    // Get type info about the components tuple
    const components_type_info = @typeInfo(@TypeOf(components));

    // Ensure we have a struct (tuple)
    if (components_type_info != .@"struct") {
        @compileError("Expected a tuple of components");
    }

    const fields = components_type_info.@"struct".fields;
    const num_components = fields.len;

    // Create arrays to hold component IDs and columns
    var component_ids: [num_components]ComponentId = undefined;
    var columns: [num_components]ComponentArray = undefined;

    // Process each component in the tuple
    inline for (fields, 0..) |field, i| {
        const component_value = @field(components, field.name);
        const ComponentType = @TypeOf(component_value);

        // Generate component ID
        component_ids[i] = componentId(ComponentType);

        // Create ComponentArray for this component type
        columns[i] = ComponentArray.init(
            allocator,
            component_ids[i],
            @sizeOf(ComponentType),
            @alignOf(ComponentType),
        );
    }

    // Calculate archetype ID
    const archetype_id = calculateId(components);

    // Allocate memory for component IDs and columns
    const name = try allocator.dupe(ComponentId, &component_ids);
    const columns_slice = try allocator.dupe(ComponentArray, &columns);

    return Archetype.init(
        archetype_id,
        name,
        columns_slice,
    );
}

pub fn addEntity(
    self: *Archetype,
    allocator: std.mem.Allocator,
    entity_id: Entity.Id,
    components: anytype,
) !void {
    try self.entity_ids.append(allocator, entity_id);

    const components_type_info = @typeInfo(@TypeOf(components));
    if (components_type_info != .@"struct") {
        @compileError("Expected a struct/tuple of components");
    }

    const fields = components_type_info.@"struct".fields;
    std.debug.assert(fields.len == self.columns.len);

    // Add each component to its corresponding column
    inline for (fields, 0..) |field, i| {
        const component_value = @field(components, field.name);
        try self.columns[i].append(allocator, &component_value);
    }
}
