//! A simple ECS (Entity-Component-System) implementation in Zig.
//!
//!
const std = @import("std");
pub const components = @import("components.zig");
pub const componentId = components.componentId;
pub const ComponentId = components.ComponentId;
pub const ComponentArray = components.ComponentArray;
pub const ComponentMeta = components.ComponentMeta;
pub const ComponentSet = components.ComponentSet;

pub const Archetype = @import("Archetype.zig");
pub const Database = @import("Database.zig");
pub const Entity = @import("Entity.zig");

const Self = @This();
test "Import embedded unit tests" {
    std.testing.refAllDecls(Self);
}

test "Import external unit tests" {
    const tests = @import("tests/tests.zig");
    std.testing.refAllDecls(tests);
}
