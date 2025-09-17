//! `ComponentSet` is a sorted, no-duplicates container of ComponentMeta.
//! It supports set operations like union and difference for archetype management.
const std = @import("std");
const root = @import("root.zig");
const ComponentMeta = root.ComponentMeta;
const componentId = root.componentId;

allocator: std.mem.Allocator,
items: std.ArrayListUnmanaged(ComponentMeta),

const ComponentSet = @This();

pub fn init(allocator: std.mem.Allocator) ComponentSet {
    return ComponentSet{
        .allocator = allocator,
        .items = .empty,
    };
}

pub fn deinit(self: *ComponentSet) void {
    self.items.deinit(self.allocator);
    self.* = undefined;
}

pub fn fromComponents(allocator: std.mem.Allocator, comptime components: anytype) !ComponentSet {
    var set = ComponentSet.init(allocator);

    const fields = std.meta.fields(@TypeOf(components));
    try set.items.ensureTotalCapacity(allocator, fields.len);

    // Create ComponentMeta for each component and add to set
    inline for (fields) |field| {
        const component_value = @field(components, field.name);
        // Handle both types and values - same pattern as ComponentMeta.from
        const ComponentT = switch (@TypeOf(component_value)) {
            type => component_value,
            else => @TypeOf(component_value),
        };
        const meta = ComponentMeta.from(ComponentT);
        try set.insertSorted(meta);
    }

    return set;
}

pub fn fromComponentsRuntime(allocator: std.mem.Allocator, components: anytype) !ComponentSet {
    var set = ComponentSet.init(allocator);

    const Tup = @TypeOf(components);
    const info = @typeInfo(Tup).@"struct";

    try set.items.ensureTotalCapacity(allocator, info.fields.len);

    // Create ComponentMeta for each component using runtime type inspection
    inline for (info.fields) |field| {
        const component_value = @field(components, field.name);
        // Handle both types and values - same pattern as fromComponents
        const ComponentT = switch (@TypeOf(component_value)) {
            type => component_value,
            else => @TypeOf(component_value),
        };
        const meta = ComponentMeta.from(ComponentT);
        try set.insertSorted(meta);
    }

    return set;
}

pub fn fromSlice(allocator: std.mem.Allocator, metas: []const ComponentMeta) !ComponentSet {
    var set = ComponentSet.init(allocator);
    try set.items.ensureTotalCapacity(allocator, metas.len);

    for (metas) |meta| {
        try set.insertSorted(meta);
    }

    return set;
}

pub fn insertSorted(self: *ComponentSet, meta: ComponentMeta) !void {
    // Binary search for insertion point
    var left: usize = 0;
    var right: usize = self.items.items.len;

    while (left < right) {
        const mid = left + (right - left) / 2;
        if (self.items.items[mid].id < meta.id) {
            left = mid + 1;
        } else if (self.items.items[mid].id > meta.id) {
            right = mid;
        } else {
            // Already exists, no need to insert
            return;
        }
    }

    try self.items.insert(self.allocator, left, meta);
}

pub fn setUnion(self: *const ComponentSet, other: *const ComponentSet) !ComponentSet {
    var result = ComponentSet.init(self.allocator);
    try result.items.ensureTotalCapacity(self.allocator, self.items.items.len + other.items.items.len);

    var i: usize = 0;
    var j: usize = 0;

    // Merge two sorted arrays, avoiding duplicates
    while (i < self.items.items.len and j < other.items.items.len) {
        const self_meta = self.items.items[i];
        const other_meta = other.items.items[j];

        if (self_meta.id < other_meta.id) {
            result.items.appendAssumeCapacity(self_meta);
            i += 1;
        } else if (self_meta.id > other_meta.id) {
            result.items.appendAssumeCapacity(other_meta);
            j += 1;
        } else {
            // Equal IDs - add only once
            result.items.appendAssumeCapacity(self_meta);
            i += 1;
            j += 1;
        }
    }

    // Add remaining elements
    while (i < self.items.items.len) {
        result.items.appendAssumeCapacity(self.items.items[i]);
        i += 1;
    }
    while (j < other.items.items.len) {
        result.items.appendAssumeCapacity(other.items.items[j]);
        j += 1;
    }

    return result;
}

pub fn setDifference(self: *const ComponentSet, other: *const ComponentSet) !ComponentSet {
    var result = ComponentSet.init(self.allocator);
    try result.items.ensureTotalCapacity(self.allocator, self.items.items.len);

    var i: usize = 0;
    var j: usize = 0;

    // Elements in self but not in other
    while (i < self.items.items.len and j < other.items.items.len) {
        const self_meta = self.items.items[i];
        const other_meta = other.items.items[j];

        if (self_meta.id < other_meta.id) {
            result.items.appendAssumeCapacity(self_meta);
            i += 1;
        } else if (self_meta.id > other_meta.id) {
            j += 1;
        } else {
            // Equal IDs - skip both
            i += 1;
            j += 1;
        }
    }

    // Add remaining elements from self
    while (i < self.items.items.len) {
        result.items.appendAssumeCapacity(self.items.items[i]);
        i += 1;
    }

    return result;
}

pub fn calculateId(self: *const ComponentSet) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (self.items.items) |meta| {
        hasher.update(std.mem.asBytes(&meta.id));
    }
    return hasher.final();
}

pub fn len(self: *const ComponentSet) usize {
    return self.items.items.len;
}

pub fn get(self: *const ComponentSet, index: usize) ?ComponentMeta {
    if (index >= self.items.items.len) return null;
    return self.items.items[index];
}
