const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Entity = root.Entity;
const Archetype = root.Archetype;
const ComponentId = root.ComponentId;
const componentId = root.componentId;

allocator: std.mem.Allocator,
database: *Database,
groups: GroupDequeue,

const GroupBy = @This();

pub fn fromTraitType(
    allocator: std.mem.Allocator,
    database: *Database,
    TraitT: anytype,
) !GroupBy {
    var group_by = GroupBy{
        .allocator = allocator,
        .database = database,
        .groups = GroupDequeue.init(allocator, {}),
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

        // Create or find the group for this key
        var group_index: ?usize = null;

        // Check if the group already exists in the dequeue
        const used = group_by.groups.items[0..group_by.groups.len];
        for (used, 0..) |g, i| {
            if (g.key == group_key) {
                group_index = i;
                break;
            }
        }

        // Create a new group if it doesn't exist
        if (group_index == null) {
            const new_group = Group.init(allocator, component_id, group_key, database);

            // Add the new group to the dequeue
            try group_by.groups.add(new_group);

            // Since PriorityDequeue reorders, we must find the index by key again
            const used_after = group_by.groups.items[0..group_by.groups.len];
            for (used_after, 0..) |g, i| {
                if (g.key == group_key) {
                    group_index = i;
                    break;
                }
            }
            // Should always find it
            std.debug.assert(group_index != null);
        }

        // Add the archetype to the group
        var group = &group_by.groups.items[group_index.?];
        try group.addArchetypeId(archetype_id);
    }

    return group_by;
}

pub fn deinit(self: *GroupBy) void {
    // Deinitialize each group - only over the used range
    const used = self.groups.items[0..self.groups.len];
    for (used) |*group| {
        group.deinit();
    }
    self.groups.deinit();
}

pub fn count(self: *const GroupBy) usize {
    return self.groups.count();
}

pub fn iterator(self: *const GroupBy) GroupIterator {
    return GroupIterator{
        .groups = &self.groups,
        .current_index = 0,
    };
}

pub const GroupDequeue = std.PriorityDequeue(Group,void, struct {
    pub fn compareFn(_: void, a: Group, b: Group) std.math.Order {
        if (a.key < b.key) return .lt;
        if (a.key > b.key) return .gt;
        return .eq;
    }
}.compareFn);

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
    groups: *const GroupDequeue,
    current_index: usize = 0,

    pub fn next(self: *GroupIterator) ?*Group {
        // Only iterate within the used range (len), not full capacity.
        if (self.current_index >= self.groups.len) return null;
        const group = &self.groups.items[self.current_index];
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