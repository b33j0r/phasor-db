//! A simple ECS (Entity-Component-System) implementation in Zig.
//!
//!
const std = @import("std");

pub const Archetype = @import("Archetype.zig");
pub const Database = @import("Database.zig");
pub const Entity = @import("Entity.zig");
pub const queries = @import("queries.zig");
pub const QueryResult = queries.QueryResult;
pub const QueryIterator = queries.QueryIterator;
pub const ComponentArray = @import("ComponentArray.zig");
pub const ComponentSet = @import("ComponentSet.zig");

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

/// `ComponentMeta` contains the metadata for a component type.
/// This was extracted from `ComponentArray` to enable better archetype management.
pub const ComponentMeta = struct {
    id: ComponentId,
    size: usize,
    alignment: u29,
    stride: usize,

    pub fn init(id: ComponentId, size: usize, alignment: u29) ComponentMeta {
        const stride = if (size == 0) 0 else std.mem.alignForward(usize, size, alignment);
        return ComponentMeta{
            .id = id,
            .size = size,
            .alignment = alignment,
            .stride = stride,
        };
    }

    pub fn from(comptime T: anytype) ComponentMeta {
        const ComponentT = if (@TypeOf(T) == type) T else @TypeOf(T);
        return ComponentMeta.init(
            componentId(ComponentT),
            @sizeOf(ComponentT),
            @alignOf(ComponentT),
        );
    }

    pub fn eql(self: ComponentMeta, other: ComponentMeta) bool {
        return self.id == other.id and
            self.size == other.size and
            self.alignment == other.alignment and
            self.stride == other.stride;
    }

    pub fn lessThan(self: ComponentMeta, other: ComponentMeta) bool {
        return self.id < other.id;
    }
};

const Self = @This();
test "Import embedded unit tests" {
    std.testing.refAllDecls(Self);
}

test "Import external unit tests" {
    const tests = @import("tests/tests.zig");
    std.testing.refAllDecls(tests);
}
