const std = @import("std");

const root = @import("root.zig");
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const Database = root.Database;
const Entity = root.Entity;
const GroupByResult = root.GroupByResult;
const componentId = root.componentId;
const extractComponentIds = root.extractComponentIds;

allocator: std.mem.Allocator,
database: *Database,
archetype_ids: std.ArrayListUnmanaged(Archetype.Id),

const QueryResult = @This();

/// Used by QuerySpec and GroupByResult
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
        if (archetype.hasComponents(component_ids.with.items) and !archetype.hasAnyComponents(component_ids.without.items)) {
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

/// Returns a slice containing all entities that match the query.
/// Caller owns the memory and must free it using the provided allocator.
pub fn listAlloc(self: *const QueryResult, allocator: std.mem.Allocator) ![]Entity {
    const total_count = self.count();
    var result = try allocator.alloc(Entity, total_count);
    errdefer allocator.free(result);

    var it = self.iterator();
    var index: usize = 0;
    while (it.next()) |entity| {
        if (index >= total_count) break; // Safety check
        result[index] = entity;
        index += 1;
    }

    return result[0..index]; // In case we got fewer entities than expected
}

/// Returns a sorted slice containing all entities that match the query.
/// Entities are sorted according to the context's lessThan function.
/// Caller owns the memory and must free it using the provided allocator.
pub fn sortAlloc(
    self: *const QueryResult, 
    allocator: std.mem.Allocator, 
    ctx: anytype,
) ![]Entity {
    // Verify at compile time that ctx has a lessThan method with the correct signature
    const Ctx = @TypeOf(ctx);
    comptime {
        if (!@hasDecl(Ctx, "lessThan")) {
            @compileError("Context type " ++ @typeName(Ctx) ++ " must have a lessThan function");
        }
    }

    // First get all entities as a slice
    const entities = try self.listAlloc(allocator);
    errdefer allocator.free(entities);

    // Sort them using the provided context's lessThan function
    std.sort.pdq(Entity, entities, ctx, Ctx.lessThan);

    return entities;
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
