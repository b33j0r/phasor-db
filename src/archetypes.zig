const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const ComponentArray = root.ComponentArray;
const Entity = root.Entity;


pub const Archetype = struct {
    id: Archetype.Id,
    name: []const ComponentId,
    columns: []ComponentArray,
    entity_ids: std.ArrayListUnmanaged(Entity.Id),

    pub const Id = u64;

    pub fn init(
        id: Id,
        name: []const ComponentId,
        columns: []ComponentArray,
    ) Archetype {
        return Archetype{
            .id = id,
            .name = name,
            .columns = columns,
            .entity_ids = .empty,
        };
    }

    pub fn getColumn(
        self: *const Archetype,
        component_id: ComponentId,
    ) ?*const ComponentArray {
        for (self.columns) |column| {
            if (column.id == component_id) {
                return &column;
            }
        }
        return null;
    }
};
