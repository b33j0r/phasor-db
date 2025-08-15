const std = @import("std");
pub const ComponentArray = @import("ComponentArray.zig");

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

/// `ComponentSet` is a sorted, no-duplicates container of ComponentMeta.
/// It supports set operations like union and difference for archetype management.
pub const ComponentSet = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(ComponentMeta),

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
            const ComponentT = @TypeOf(component_value);
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
};
