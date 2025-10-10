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

/// Get a non-derived component pointer.
/// If called with a derived component (a type that declares __derived__), this is a compile-time error.
pub fn get(self: *const Entity, comptime T: type) ?*T {
    if (@hasDecl(T, "__derived__")) {
        @compileError("Entity.get cannot be used with derived components. Use Entity.getAlloc(allocator, T) instead.");
    }

    const archetype = self.database.archetypes.get(self.archetype_id) orelse return null;
    if (archetype.getColumn(componentId(T))) |column| {
        return column.get(self.row_index, T);
    }

    return null;
}

/// A small RAII-style wrapper for pointers returned by getAlloc.
/// - For non-derived components, deinit() is a no-op.
/// - For derived components, deinit() frees the allocated storage.
pub fn Owned(comptime T: type) type {
    return struct {
        /// Pointer to the component value. Always valid while this wrapper is alive.
        ptr: *T,
        /// Allocator used when allocating derived values (null for non-derived).
        allocator: ?std.mem.Allocator = null,
        /// True when the value was computed from a derived component and thus heap-allocated.
        is_derived: bool = false,

        const Self = @This();
        pub fn deinit(self: *const Self) void {
            if (self.is_derived) {
                if (self.allocator) |a| {
                    a.destroy(self.ptr);
                }
            }
            // Note: do not mutate self here so that deinit can be called on const wrappers
        }
    };
}

/// Robust accessor that supports both non-derived and derived components.
/// - Non-derived: returns a wrapper around an existing pointer (no allocation); deinit() is a no-op.
/// - Derived: computes the value with __derived__.derive, allocates storage, and returns it; deinit() frees it.
pub fn getAlloc(self: *const Entity, allocator: std.mem.Allocator, comptime T: type) ?Owned(T) {
    // Derived component path
    if (@hasDecl(T, "__derived__")) {
        if (T.__derived__.derive(self.*)) |value| {
            const p = allocator.create(T) catch return null;
            p.* = value;
            return Owned(T){ .ptr = p, .allocator = allocator, .is_derived = true };
        } else {
            return null;
        }
    }

    // Non-derived path: return direct pointer into storage wrapped in Owned<T>
    const archetype = self.database.archetypes.get(self.archetype_id) orelse return null;
    if (archetype.getColumn(componentId(T))) |column| {
        const p = column.get(self.row_index, T) orelse return null;
        return Owned(T){ .ptr = p, .allocator = null, .is_derived = false };
    }

    // Try to treat as a bundle (struct of components)
    if (@typeInfo(T) == .@"struct") {
        if (self.extractBundleAlloc(T, allocator)) |extracted| {
            return Owned(T){ .ptr = extracted, .allocator = allocator, .is_derived = true };
        }
    }

    return null;
}

fn extractBundleAlloc(self: *const Entity, T: type, allocator: std.mem.Allocator) ?*T {
    const fields = std.meta.fields(T);
    const result = allocator.create(T) catch return null;

    // Initialize all fields by getting the corresponding components from the entity
    inline for (fields) |field| {
        const component_ptr = self.get(field.type) orelse {
            // Failed to get required component, cleanup and return null
            allocator.destroy(result);
            return null;
        };
        @field(result, field.name) = component_ptr.*;
    }

    return result;
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
