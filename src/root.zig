//! A simple ECS (Entity-Component-System) implementation in Zig.
const std = @import("std");

pub const Archetype = @import("Archetype.zig");
pub const Database = @import("Database.zig");
pub const Entity = @import("Entity.zig");
pub const Query = @import("Query.zig");
pub const ComponentArray = @import("ComponentArray.zig");
pub const ComponentSet = @import("ComponentSet.zig");
pub const ComponentMeta = @import("ComponentMeta.zig");

/// `ComponentId` is a unique identifier for a component type. Use
/// `componentId` to generate a `ComponentId` from a type.
pub const ComponentId = u64;

/// `componentId` generates a unique identifier for a component type or value.
/// It uses the fully-qualified type name as input to a hash function.
pub fn componentId(comptime T: anytype) ComponentId {
    const ComponentT = if (@TypeOf(T) == type) T else @TypeOf(T);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(@typeName(ComponentT));
    return hasher.final();
}


const Self = @This();
test "Import embedded unit tests" {
    std.testing.refAllDecls(Self);
}

test "Import external unit tests" {
    const tests = @import("tests/tests.zig");
    std.testing.refAllDecls(tests);
}
