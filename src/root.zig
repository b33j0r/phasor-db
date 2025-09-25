//! A simple ECS (Entity-Component-System) implementation in Zig.
const std = @import("std");

pub const Archetype = @import("Archetype.zig");
pub const ComponentArray = @import("ComponentArray.zig");
pub const ComponentMeta = @import("ComponentMeta.zig");
pub const ComponentSet = @import("ComponentSet.zig");
pub const Database = @import("Database.zig");
pub const Entity = @import("Entity.zig");
pub const GroupByResult = @import("GroupByResult.zig");
pub const QuerySpec = @import("QuerySpec.zig");
pub const QueryResult = @import("QueryResult.zig");
pub const Trait = @import("Trait.zig");
pub const Without = QuerySpec.Without;
pub const Drop = @import("Drop.zig");

/// `ComponentId` is a unique identifier for a component type. Use
/// `componentId` to generate a `ComponentId` from a type.
pub const ComponentId = u64;

/// `componentId` generates a unique identifier for a component type or value.
/// It uses the fully-qualified type name as input to a hash function.
/// For components with traits that have group keys, the group key is included in the hash.
pub fn componentId(comptime T: anytype) ComponentId {
    const ComponentT = if (@TypeOf(T) == type) T else @TypeOf(T);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(@typeName(ComponentT));

    // If the component has a trait with a group key, include it in the hash
    if (@hasDecl(ComponentT, "__trait__") and @hasDecl(ComponentT, "__group_key__")) {
        const group_key_bytes = std.mem.asBytes(&ComponentT.__group_key__);
        hasher.update(group_key_bytes);
    }

    return hasher.final();
}

/// Return type of extractComponentIds
pub const ExtractedComponentIds = struct {
    with: std.ArrayListUnmanaged(ComponentId) = .empty,
    without: std.ArrayListUnmanaged(ComponentId) = .empty,

    pub const empty = ExtractedComponentIds{};

    pub fn deinit(self: *ExtractedComponentIds, allocator: std.mem.Allocator) void {
        self.with.deinit(allocator);
        self.without.deinit(allocator);
    }
};

/// Helper function to extract component IDs from a component specification
pub fn extractComponentIds(allocator: std.mem.Allocator, components: anytype) !ExtractedComponentIds {
    var component_ids: ExtractedComponentIds = .empty;
    const spec_info = @typeInfo(@TypeOf(components)).@"struct";
    inline for (spec_info.fields) |field| {
        const field_value = @field(components, field.name);
        const field_type = @TypeOf(field_value);

        // Skip derived types from filtering so queries always match
        const is_type = field_type == type;
        const value_type = if (is_type) field_value else field_type;
        if (@hasDecl(value_type, "__derived__")) {
            continue;
        }

        const without = @hasDecl(value_type, "__without__");

        // Handle the case where the field contains a type (not an instance)
        const component_id = if (without)
            componentId(value_type.__without__)
        else if (is_type)
            componentId(field_value) // field_value is the actual type
        else
            componentId(field_type); // field_value is an instance, so get its type

        if (without) {
            try component_ids.without.append(allocator, component_id);
        } else {
            try component_ids.with.append(allocator, component_id);
        }
    }
    return component_ids;
}

const Self = @This();
test "Import embedded unit tests" {
    std.testing.refAllDecls(Self);
}
