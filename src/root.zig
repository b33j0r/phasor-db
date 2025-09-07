//! A simple ECS (Entity-Component-System) implementation in Zig.
const std = @import("std");

pub const Archetype = @import("Archetype.zig");
pub const ComponentArray = @import("ComponentArray.zig");
pub const ComponentMeta = @import("ComponentMeta.zig");
pub const ComponentSet = @import("ComponentSet.zig");
pub const Database = @import("Database.zig");
pub const Entity = @import("Entity.zig");
pub const GroupByResult = @import("GroupByResult.zig");
pub const Query = @import("systems.zig").Query;
pub const Without = @import("systems.zig").Without;
pub const Mut = @import("systems.zig").Mut;
pub const QuerySpec = @import("QuerySpec.zig");
pub const QueryResult = @import("QueryResult.zig");
pub const ResourceManager = @import("ResourceManager.zig");
pub const Schedule = @import("Schedule.zig");
pub const System = @import("systems.zig").System;
pub const Trait = @import("Trait.zig");
pub const Transaction = @import("Transaction.zig");

/// `ComponentId` is a unique identifier for a component type. Use
/// `componentId` to generate a `ComponentId` from a type.
pub const ComponentId = u64;

/// `componentId` generates a unique identifier for a component type or value.
/// It uses the fully-qualified type name as input to a hash function.
/// For components with traits that have group keys, the group key is included in the hash.
pub fn componentId(comptime T: anytype) ComponentId {
    const ComponentT = if (@TypeOf(T) == type) T else @TypeOf(T);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(@typeName(ComponentT));

    // If the component has a trait with a group key, include it in the hash
    if (@hasDecl(ComponentT, "__trait__") and @hasDecl(ComponentT, "__group_key__")) {
        const group_key_bytes = std.mem.asBytes(&ComponentT.__group_key__);
        hasher.update(group_key_bytes);
    }

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
