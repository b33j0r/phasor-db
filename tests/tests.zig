pub const test_archetypes = @import("test_archetypes.zig");
pub const test_components = @import("test_components.zig");
pub const test_database = @import("test_database.zig");
pub const test_queries = @import("test_queries.zig");
pub const test_derived = @import("test_derived.zig");

test "Import tests" {
    _ = test_archetypes;
    _ = test_components;
    _ = test_database;
    _ = test_queries;
    _ = test_derived;
}
