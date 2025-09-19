const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const QueryResult = root.QueryResult;
const extractComponentIds = root.extractComponentIds;
const ExtractedComponentIds = root.ExtractedComponentIds;

/// QuerySpec is a specification of components (and optional archetype filter) that can be executed on a Database.
allocator: std.mem.Allocator,
component_ids: ExtractedComponentIds = .empty,
/// Optional pre-filter of archetype ids to restrict execution to a subset
archetype_filter: ?std.ArrayListUnmanaged(Archetype.Id) = null,

pub fn Without(comptime ComponentT: type) type {
    return struct {
        pub const __without__ = ComponentT;
    };
}

const QuerySpec = @This();

pub fn fromComponentTypes(allocator: std.mem.Allocator, spec: anytype) !QuerySpec {
    return QuerySpec{
        .allocator = allocator,
        .component_ids = try extractComponentIds(allocator, spec),
        .archetype_filter = null,
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
            if (archetype.hasComponents(self.component_ids.with.items) and !archetype.hasAnyComponents(self.component_ids.without.items)) {
                try result_ids.append(self.allocator, archetype.id);
            }
        }
    } else {
        var it = db.archetypes.iterator();
        while (it.next()) |entry| {
            const archetype = entry.value_ptr;
            if (archetype.hasComponents(self.component_ids.with.items) and !archetype.hasAnyComponents(self.component_ids.without.items)) {
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
