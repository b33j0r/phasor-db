pub const test_components = @import("test_components.zig");
pub const test_archetypes = @import("test_archetypes.zig");
pub const test_database = @import("test_database.zig");
pub const test_resources = @import("test_resources.zig");

const std = @import("std");
const Self = @This();

test "Import tests" {
    std.testing.refAllDecls(Self);
}
