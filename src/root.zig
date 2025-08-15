//! A simple ECS (Entity-Component-System) implementation in Zig.
//!
//!
const std = @import("std");
pub const components = @import("components.zig");
pub const componentId = components.componentId;
pub const ComponentId = components.ComponentId;
pub const ComponentArray = components.ComponentArray;

pub const Archetype = @import("Archetype.zig");

pub const Database = @import("Database.zig");

/// Entity is a view of the components associated with an entity.
pub const Entity = struct {
    id: Id,
    database: *Database,
    archetype_id: Archetype.Id,
    row_index: usize,

    pub const Id = usize;

    pub fn get(self: *const Entity, comptime T: type) ?*T {
        const archetype = self.database.archetypes.get(self.archetype_id) orelse return null;
        const column = archetype.getColumn(componentId(T)) orelse return null;
        return column.get(self.row_index, T);
    }
};

const Self = @This();
test "Import embedded unit tests" {
    std.testing.refAllDeclsRecursive(Self);
}

test "Import external unit tests" {
    const tests = @import("tests/tests.zig");
    std.testing.refAllDeclsRecursive(tests);
}
