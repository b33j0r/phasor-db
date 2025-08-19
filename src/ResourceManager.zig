const std = @import("std");
const root = @import("root.zig");

pub const ResourceId = u64;

pub fn resourceId(T: anytype) ResourceId {
    var hasher = std.hash.Wyhash.init(0);
    const ResourceT = if (@TypeOf(T) == type)
        T
    else
        @TypeOf(T);
    std.hash.autoHash(&hasher, @typeName(ResourceT));
    return hasher.final();
}

const ResourceEntry = struct {
    ptr: *anyopaque,
    destructor: *const fn (*anyopaque, std.mem.Allocator) void,
};

pub const ResourceManager = @This();

allocator: std.mem.Allocator,
data: std.AutoHashMapUnmanaged(ResourceId, ResourceEntry) = .{},

pub fn init(allocator: std.mem.Allocator) ResourceManager {
    return ResourceManager{
        .allocator = allocator,
    };
}

pub fn deinit(self: *ResourceManager) void {
    // Free all stored resources using their proper destructors
    var iterator = self.data.iterator();
    while (iterator.next()) |entry| {
        const resource_entry = entry.value_ptr.*;
        resource_entry.destructor(resource_entry.ptr, self.allocator);
    }
    self.data.deinit(self.allocator);
}

pub fn insert(self: *ResourceManager, resource: anytype) !void {
    const T = @TypeOf(resource);
    const id = resourceId(T);

    // If resource already exists, free the old one
    if (self.data.get(id)) |old_entry| {
        old_entry.destructor(old_entry.ptr, self.allocator);
    }

    const ptr = try self.allocator.create(T);
    ptr.* = resource;

    const entry = ResourceEntry{
        .ptr = @ptrCast(ptr),
        .destructor = struct {
            fn destroy(resource_ptr: *anyopaque, alloc: std.mem.Allocator) void {
                const typed_ptr: *T = @ptrCast(@alignCast(resource_ptr));
                alloc.destroy(typed_ptr);
            }
        }.destroy,
    };

    try self.data.put(self.allocator, id, entry);
}

pub fn get(self: *ResourceManager, comptime T: type) ?*T {
    const id = resourceId(T);
    if (self.data.get(id)) |entry| {
        return @as(*T, @ptrCast(@alignCast(entry.ptr)));
    }
    return null;
}

pub fn has(self: *ResourceManager, comptime T: type) bool {
    const id = resourceId(T);
    return self.data.contains(id);
}

pub fn remove(self: *ResourceManager, comptime T: type) bool {
    const id = resourceId(T);
    if (self.data.fetchRemove(id)) |kv| {
        const entry = kv.value;
        entry.destructor(entry.ptr, self.allocator);
        return true;
    }
    return false;
}

