const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;

allocator: std.mem.Allocator,
database: *Database,
groups: std.ArrayListUnmanaged(Group),

const GroupBy = @This();

pub fn fromTraitType(
    allocator: std.mem.Allocator,
    database: *Database,
    TraitT: anytype,
) !GroupBy {
    var group_by = GroupBy{
        .allocator = allocator,
        .database = database,
        .groups = .empty,
    };

    // Iterate over all archetypes and group entities by the trait key
    var archetype_iterator = database.archetypes.iterator();
    const trait_id = componentId(TraitT);
    while (archetype_iterator.next()) |entry| {
        const archetype_id = entry.key_ptr.*;
        const archetype = entry.value_ptr.*;
        const trait_column = archetype.getColumn(trait_id) orelse continue;
        const component_id = trait_column.meta.id;
        const trait = trait_column.meta.trait orelse continue;
        const group_key = switch (trait.kind) {
            .Grouped => |grouped| grouped.group_key,
            else => continue, // Only handle Grouped traits
        };

        // Find or create the group for this key
        var found_group: ?*Group = null;
        for (group_by.groups.items) |*group| {
            if (group.key == group_key) {
                found_group = group;
                break;
            }
        }

        // Create a new group if it doesn't exist
        if (found_group == null) {
            const new_group = Group.init(allocator, component_id, group_key, database);
            try group_by.groups.append(allocator, new_group);
            found_group = &group_by.groups.items[group_by.groups.items.len - 1];
        }

        // Add the archetype to the group
        try found_group.?.addArchetypeId(archetype_id);
    }

    // Sort groups by key for consistent ordering
    std.mem.sort(Group, group_by.groups.items, {}, struct {
        fn lessThan(_: void, a: Group, b: Group) bool {
            return a.key < b.key;
        }
    }.lessThan);

    return group_by;
}

pub fn deinit(self: *GroupBy) void {
    for (self.groups.items) |*group| {
        group.deinit();
    }
    self.groups.deinit(self.allocator);
}

pub fn count(self: *const GroupBy) usize {
    return self.groups.items.len;
}

pub fn iterator(self: *const GroupBy) GroupIterator {
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
