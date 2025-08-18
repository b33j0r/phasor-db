const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;

allocator: std.mem.Allocator,
database: *Database,
archetype_ids: std.ArrayListUnmanaged(Archetype.Id),

const Query = @This();

pub fn deinit(self: *Query) void {
    self.archetype_ids.deinit(self.allocator);
}

pub fn count(self: *const Query) usize {
    // add up the entity counts in all matching archetypes
    var total_count: usize = 0;
    for (self.archetype_ids.items) |archetype_id| {
        const archetype = self.database.archetypes.get(archetype_id) orelse continue;
        total_count += archetype.entity_ids.items.len;
    }
    return total_count;
}

pub fn iterator(self: *const Query) Iterator {
    return Iterator{
        .query = self,
        .current_archetype_index = 0,
        .current_entity_index = 0,
    };
}

pub fn first(self: *const Query) ?Entity {
    var it = self.iterator();
    return it.next();
}

/// `Iterator` is used to iterate over entities that match the query.
pub const Iterator = struct {
    query: *const Query,
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
