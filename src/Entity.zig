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

pub fn has(self: *const Entity, comptime T: type) bool {
    const archetype = self.database.archetypes.get(self.archetype_id) orelse return false;
    return archetype.hasComponents(&.{componentId(T)});
}

pub fn set(self: *Entity, value: anytype) !void {
    const T = @TypeOf(value);
    const archetype = self.database.archetypes.getPtr(self.archetype_id) orelse return error.ArchetypeNotFound;
    const column = archetype.getColumnMut(componentId(T)) orelse return error.ComponentNotFound;
    return column.set(self.row_index, value);
}
