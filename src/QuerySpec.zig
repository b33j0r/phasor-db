const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const QueryResult = root.QueryResult;

/// QuerySpec is a specification of components (and optional archetype filter) that can be executed on a Database.
allocator: std.mem.Allocator,
component_ids: std.ArrayListUnmanaged(ComponentId) = .empty,
/// Optional pre-filter of archetype ids to restrict execution to a subset
archetype_filter: ?std.ArrayListUnmanaged(Archetype.Id) = null,

const QuerySpec = @This();

/// Helper function to extract component IDs from a component specification
fn extractComponentIds(allocator: std.mem.Allocator, components: anytype) !std.ArrayListUnmanaged(ComponentId) {
    var component_ids: std.ArrayListUnmanaged(ComponentId) = .empty;
    const spec_info = @typeInfo(@TypeOf(components)).@"struct";
    inline for (spec_info.fields) |field| {
        const field_value = @field(components, field.name);
        const field_type = @TypeOf(field_value);
        const id = if (field_type == type) componentId(field_value) else componentId(field_type);
        try component_ids.append(allocator, id);
    }
    return component_ids;
}

pub fn fromComponentTypes(allocator: std.mem.Allocator, spec: anytype) !QuerySpec {
    return QuerySpec{
        .allocator = allocator,
        .component_ids = try extractComponentIds(allocator, spec),
        .archetype_filter = null,
    };
}

pub fn fromComponentTypesAndArchetypeIds(
    allocator: std.mem.Allocator,
    archetype_ids: []const Archetype.Id,
    components: anytype,
) !QuerySpec {
    var filter = std.ArrayListUnmanaged(Archetype.Id).empty;
    try filter.appendSlice(allocator, archetype_ids);
    return QuerySpec{
        .allocator = allocator,
        .component_ids = try extractComponentIds(allocator, components),
        .archetype_filter = filter,
    };
}

pub fn deinit(self: *QuerySpec) void {
    if (self.archetype_filter) |*flt| flt.deinit(self.allocator);
    self.component_ids.deinit(self.allocator);
}

pub fn execute(self: *const QuerySpec, db: *Database) !QueryResult {
    var result_ids = std.ArrayListUnmanaged(Archetype.Id).empty;
    if (self.archetype_filter) |flt| {
        for (flt.items) |archetype_id| {
            const archetype = db.archetypes.get(archetype_id) orelse continue;
            if (archetype.hasComponents(self.component_ids.items)) {
                try result_ids.append(self.allocator, archetype.id);
            }
        }
    } else {
        var it = db.archetypes.iterator();
        while (it.next()) |entry| {
            const archetype = entry.value_ptr;
            if (archetype.hasComponents(self.component_ids.items)) {
                try result_ids.append(self.allocator, archetype.id);
            }
        }
    }
    return QueryResult{
        .allocator = self.allocator,
        .database = db,
        .archetype_ids = result_ids,
    };
}
