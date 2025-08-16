const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;

pub const QueryResult = struct {
    allocator: std.mem.Allocator,
    database: *Database,
    archetype_ids: std.ArrayListUnmanaged(Archetype.Id),

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

    pub fn iterator(self: *const QueryResult) QueryIterator {
        return QueryIterator{
            .query = self,
            .current_archetype_index = 0,
            .current_entity_index = 0,
        };
    }
};

pub const QueryIterator = struct {
    query: *const QueryResult,
    current_archetype_index: usize = 0,
    current_entity_index: usize = 0,

    pub fn next(self: *QueryIterator) ?Entity {
        while (self.current_archetype_index < self.query.archetype_ids.items.len) {
            const archetype_id = self.query.archetype_ids.items[self.current_archetype_index];
            const archetype = self.query.database.archetypes.get(archetype_id) orelse {
                self.current_archetype_index += 1;
                self.current_entity_index = 0;
                continue;
            };

            if (self.current_entity_index < archetype.entity_ids.items.len) {
                const entity_id = archetype.entity_ids.items[self.current_entity_index];
                const entity = self.query.database.getEntity(entity_id) orelse {
                    self.current_entity_index += 1;
                    continue;
                };
                self.current_entity_index += 1;
                return entity;
            } else {
                self.current_archetype_index += 1;
                self.current_entity_index = 0;
            }
        }
        return null; // No more entities
    }
};