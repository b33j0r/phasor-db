const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const GroupByResult = root.GroupByResult;

allocator: std.mem.Allocator,
database: *Database,
archetype_ids: std.ArrayListUnmanaged(Archetype.Id),

const QueryResult = @This();

/// Helper function to extract component IDs from a component specification
fn extractComponentIds(allocator: std.mem.Allocator, components: anytype) !std.ArrayListUnmanaged(ComponentId) {
    var component_ids: std.ArrayListUnmanaged(ComponentId) = .empty;
    const spec_info = @typeInfo(@TypeOf(components)).@"struct";
    inline for (spec_info.fields) |field| {
        const field_value = @field(components, field.name);
        const field_type = @TypeOf(field_value);

        // Handle the case where the field contains a type (not an instance)
        const component_id = if (field_type == type)
            componentId(field_value) // field_value is the actual type
        else
            componentId(field_type); // field_value is an instance, so get its type

        try component_ids.append(allocator, component_id);
    }
    return component_ids;
}

pub fn fromComponentTypes(
    allocator: std.mem.Allocator,
    database: *Database,
    spec: anytype,
) !QueryResult {
    var archetype_ids: std.ArrayListUnmanaged(Archetype.Id) = .empty;
    var component_ids = try extractComponentIds(allocator, spec);
    defer component_ids.deinit(allocator);

    var it = database.archetypes.iterator();
    while (it.next()) |entry| {
        const archetype = entry.value_ptr;
        if (archetype.hasComponents(component_ids.items)) {
            try archetype_ids.append(allocator, archetype.id);
        }
    }

    return QueryResult{
        .allocator = allocator,
        .database = database,
        .archetype_ids = archetype_ids,
    };
}

pub fn fromComponentTypesAndArchetypeIds(
    allocator: std.mem.Allocator,
    database: *Database,
    archetype_ids: []const Archetype.Id,
    components: anytype,
) !QueryResult {
    var component_ids = try extractComponentIds(allocator, components);
    defer component_ids.deinit(allocator);

    var query_archetype_ids: std.ArrayListUnmanaged(Archetype.Id) = .empty;

    for (archetype_ids) |archetype_id| {
        const archetype = database.archetypes.get(archetype_id) orelse continue;
        if (archetype.hasComponents(component_ids.items)) {
            try query_archetype_ids.append(allocator, archetype.id);
        }
    }

    return QueryResult{
        .allocator = allocator,
        .database = database,
        .archetype_ids = query_archetype_ids,
    };
}

pub fn deinit(self: *QueryResult) void {
    self.archetype_ids.deinit(self.allocator);
}

pub fn count(self: *const QueryResult) usize {
    // add up the entity counts in all matching archetypes
    var total_count: usize = 0;
    for (self.archetype_ids.items) |archetype_id| {
        const archetype = self.database.archetypes.get(archetype_id) orelse continue;
        total_count += archetype.entity_ids.items.len;
    }
    return total_count;
}

pub fn iterator(self: *const QueryResult) Iterator {
    return Iterator{
        .query = self,
        .current_archetype_index = 0,
        .current_entity_index = 0,
    };
}

pub fn first(self: *const QueryResult) ?Entity {
    var it = self.iterator();
    return it.next();
}

pub fn groupBy(self: *const QueryResult, TraitT: anytype) !root.GroupByResult {
    return GroupByResult.fromTraitTypeAndArchetypeIds(
        self.allocator,
        self.database,
        self.archetype_ids.items,
        TraitT,
    );
}

/// `Iterator` is used to iterate over entities that match the query.
pub const Iterator = struct {
    query: *const QueryResult,
    current_archetype_index: usize = 0,
    current_entity_index: usize = 0,
    current_archetype: ?*Archetype = null,

    /// Returns the next entity that matches the query.
    /// If there are no more entities, returns null.
    pub fn next(self: *Iterator) ?Entity {
        while (self.current_archetype_index < self.query.archetype_ids.items.len) {
            // Fetch archetype pointer only when moving to a new archetype
            if (self.current_archetype == null) {
                const archetype_id = self.query.archetype_ids.items[self.current_archetype_index];
                self.current_archetype = self.query.database.archetypes.getPtr(archetype_id);
            }

            std.debug.assert(self.current_archetype != null);
            const archetype = self.current_archetype.?;

            if (self.current_entity_index < archetype.entity_ids.items.len) {
                const entity_id = archetype.entity_ids.items[self.current_entity_index];

                const entity = Entity{
                    .id = entity_id,
                    .database = self.query.database,
                    .archetype_id = self.query.archetype_ids.items[self.current_archetype_index],
                    .row_index = self.current_entity_index,
                };

                self.current_entity_index += 1;
                return entity;
            } else {
                // Move to next archetype
                self.current_archetype_index += 1;
                self.current_entity_index = 0;
                self.current_archetype = null;
            }
        }
        return null;
    }
};
