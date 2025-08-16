//! Entity is a view of the components associated with an entity.
const std = @import("std");
const root = @import("root.zig");
const Database = root.Database;
const Archetype = root.Archetype;
const componentId = root.componentId;

id: Id,
database: *Database,
archetype_id: Archetype.Id,
row_index: usize,

const Entity = @This();
pub const Id = usize;

pub fn get(self: *const Entity, comptime T: type) ?*T {
    const archetype = self.database.archetypes.get(self.archetype_id) orelse return null;
    const column = archetype.getColumn(componentId(T)) orelse return null;
    return column.get(self.row_index, T);
}
