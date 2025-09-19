const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const QueryResult = root.QueryResult;

allocator: std.mem.Allocator,
database: *Database,
groups: std.ArrayListUnmanaged(Group),

const GroupByResult = @This();

pub fn fromTraitType(
    allocator: std.mem.Allocator,
    database: *Database,
    TraitT: anytype,
) !GroupByResult {
    var group_by = GroupByResult{
        .allocator = allocator,
        .database = database,
        .groups = .empty,
    };

    // Get all archetype IDs from the database
    var archetype_ids = std.ArrayListUnmanaged(Archetype.Id).empty;
    defer archetype_ids.deinit(allocator);

    var archetype_iterator = database.archetypes.iterator();
    while (archetype_iterator.next()) |entry| {
        try archetype_ids.append(allocator, entry.key_ptr.*);
    }

    const trait_id = componentId(TraitT);
    group_by.groups = try groupArchetypesByTrait(allocator, database, archetype_ids.items, trait_id);

    return group_by;
}

// Used by QueryResult
pub fn fromTraitTypeAndArchetypeIds(
    allocator: std.mem.Allocator,
    database: *Database,
    archetype_ids: []const Archetype.Id,
    TraitT: anytype,
) !GroupByResult {
    var group_by = GroupByResult{
        .allocator = allocator,
        .database = database,
        .groups = .empty,
    };

    const trait_id = componentId(TraitT);
    group_by.groups = try groupArchetypesByTrait(allocator, database, archetype_ids, trait_id);

    return group_by;
}

/// Generic function to group archetypes by trait key
fn groupArchetypesByTrait(
    allocator: std.mem.Allocator,
    database: *Database,
    archetype_ids: []const Archetype.Id,
    trait_id: ComponentId,
) !std.ArrayListUnmanaged(Group) {
    var groups = std.ArrayListUnmanaged(Group).empty;

    for (archetype_ids) |archetype_id| {
        const archetype = database.archetypes.getPtr(archetype_id) orelse continue;

        // Look through all columns in this archetype to find components with the specified trait
        for (archetype.columns) |*column| {
            const trait = column.meta.trait orelse continue;

            // Check if this component's trait matches the trait we're grouping by
            if (trait.id != trait_id) continue;

            const group_key = switch (trait.kind) {
                .Grouped => |grouped| grouped.group_key,
                else => continue, // Only handle Grouped traits
            };

            // Find or create the group for this key
            var found_group: ?*Group = null;
            for (groups.items) |*group| {
                if (group.key == group_key) {
                    found_group = group;
                    break;
                }
            }

            // Create a new group if it doesn't exist
            if (found_group == null) {
                const new_group = Group.init(allocator, column.meta.id, group_key, database);
                try groups.append(allocator, new_group);
                found_group = &groups.items[groups.items.len - 1];
            }

            // Add the archetype to the group (only once per archetype)
            var already_added = false;
            for (found_group.?.archetype_ids.items) |existing_id| {
                if (existing_id == archetype_id) {
                    already_added = true;
                    break;
                }
            }
            if (!already_added) {
                try found_group.?.addArchetypeId(archetype_id);
            }
        }
    }

    // Sort groups by key for consistent ordering
    std.mem.sort(Group, groups.items, {}, struct {
        fn lessThan(_: void, a: Group, b: Group) bool {
            return a.key < b.key;
        }
    }.lessThan);

    return groups;
}

pub fn deinit(self: *GroupByResult) void {
    for (self.groups.items) |*group| {
        group.deinit();
    }
    self.groups.deinit(self.allocator);
}

pub fn count(self: *const GroupByResult) usize {
    return self.groups.items.len;
}

pub fn iterator(self: *const GroupByResult) GroupIterator {
    return GroupIterator{
        .groups = self.groups.items,
        .current_index = 0,
    };
}

/// `Group` represents a collection of entities that share the same group key under a trait.
pub const Group = struct {
    component_id: ComponentId,
    key: i32,
    allocator: std.mem.Allocator,
    database: *Database,
    archetype_ids: std.ArrayListUnmanaged(Archetype.Id) = .empty,

    pub fn init(allocator: std.mem.Allocator, component_id: ComponentId, key: i32, database: *Database) Group {
        return Group{
            .component_id = component_id,
            .key = key,
            .allocator = allocator,
            .database = database,
            .archetype_ids = .empty,
        };
    }

    pub fn deinit(self: *Group) void {
        self.archetype_ids.deinit(self.allocator);
    }

    pub fn addArchetypeId(self: *Group, archetype_id: Archetype.Id) !void {
        try self.archetype_ids.append(self.allocator, archetype_id);
    }

    /// Group this group's entities by another trait to create nested groups
    pub fn groupBy(self: *const Group, TraitT: anytype) !GroupByResult {
        // Check if this group has any archetype IDs before proceeding
        if (self.archetype_ids.items.len == 0) {
            return GroupByResult{
                .allocator = self.allocator,
                .database = self.database,
                .groups = .empty,
            };
        }

        var group_by = GroupByResult{
            .allocator = self.allocator,
            .database = self.database,
            .groups = .empty,
        };

        const trait_id = componentId(TraitT);
        group_by.groups = try groupArchetypesByTrait(self.allocator, self.database, self.archetype_ids.items, trait_id);

        return group_by;
    }

    /// Do a subquery on this group
    pub fn query(self: *const Group, components: anytype) !root.QueryResult {
        // Handle empty group case gracefully
        if (self.archetype_ids.items.len == 0) {
            return root.QueryResult{
                .allocator = self.allocator,
                .database = self.database,
                .archetype_ids = .empty,
            };
        }

        return QueryResult.fromComponentTypesAndArchetypeIds(
            self.allocator,
            self.database,
            self.archetype_ids.items,
            components,
        );
    }

    pub fn iterator(self: *const Group) EntityIterator {
        return EntityIterator{
            .group = self,
            .current_archetype_index = 0,
            .current_entity_index = 0,
        };
    }
};

/// `GroupIterator` is used to iterate over groups in the result.
pub const GroupIterator = struct {
    groups: []const Group,
    current_index: usize,

    pub fn next(self: *GroupIterator) ?*const Group {
        if (self.current_index >= self.groups.len) return null;
        const group = &self.groups[self.current_index];
        self.current_index += 1;
        return group;
    }
};

/// `EntityIterator` is used to iterate over entities in a group.
pub const EntityIterator = struct {
    group: *const Group,
    current_archetype_index: usize = 0,
    current_entity_index: usize = 0,

    pub fn next(self: *EntityIterator) ?Entity {
        while (self.current_archetype_index < self.group.archetype_ids.items.len) {
            const archetype_id = self.group.archetype_ids.items[self.current_archetype_index];
            const archetype = self.group.database.archetypes.getPtr(archetype_id) orelse {
                self.current_archetype_index += 1;
                self.current_entity_index = 0;
                continue;
            };

            if (self.current_entity_index < archetype.entity_ids.items.len) {
                const entity_id = archetype.entity_ids.items[self.current_entity_index];
                const entity = Entity{
                    .id = entity_id,
                    .database = self.group.database,
                    .archetype_id = archetype_id,
                    .row_index = self.current_entity_index,
                };
                self.current_entity_index += 1;
                return entity;
            } else {
                self.current_archetype_index += 1;
                self.current_entity_index = 0;
            }
        }
        return null;
    }
};
