pub const test_archetypes = @import("test_archetypes.zig");
pub const test_components = @import("test_components.zig");
pub const test_database = @import("test_database.zig");
pub const test_queries = @import("test_queries.zig");
pub const test_resources = @import("test_resources.zig");
pub const test_systems = @import("test_systems.zig");
pub const test_transactions = @import("test_transactions.zig");

const std = @import("std");
const Self = @This();

test "Import tests" {
    std.testing.refAllDecls(Self);
}
