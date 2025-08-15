const std = @import("std");

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

    fn insertSorted(self: *ComponentSet, meta: ComponentMeta) !void {
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

/// `ComponentArray` is a dynamic type-erased array that holds components of a specific type.
/// It is used to create columns in each `Archetype` table.
pub const ComponentArray = struct {
    allocator: std.mem.Allocator,
    meta: ComponentMeta,
    capacity: usize = 0,
    len: usize = 0,
    bytes: []u8 = &[_]u8{},

    /// Minimum capacity allocated when the array becomes occupied.
    /// This reduces the frequency of reallocations for small arrays.
    pub const min_occupied_capacity = 8;

    pub fn init(
        allocator: std.mem.Allocator,
        meta: ComponentMeta,
    ) ComponentArray {
        return ComponentArray{
            .allocator = allocator,
            .meta = meta,
        };
    }

    pub fn initFromType(
        allocator: std.mem.Allocator,
        id: ComponentId,
        size: usize,
        alignment: u29,
    ) ComponentArray {
        const meta = ComponentMeta.init(id, size, alignment);
        return ComponentArray.init(allocator, meta);
    }

    pub fn from(
        allocator: std.mem.Allocator,
        comptime T: anytype,
    ) !ComponentArray {
        const hasValue = @TypeOf(T) != type;
        const ComponentT = if (hasValue) @TypeOf(T) else T;
        const meta = ComponentMeta.from(ComponentT);
        var component_array = ComponentArray.init(allocator, meta);
        if (hasValue) {
            try component_array.append(T);
        }
        return component_array;
    }

    pub fn deinit(self: *ComponentArray) void {
        if (self.bytes.len > 0) {
            self.allocator.free(self.bytes);
        }
        self.* = undefined;
    }

    pub fn get(self: *const ComponentArray, index: usize, comptime T: type) ?*T {
        if (self.meta.size == 0 or index >= self.len) return null;
        const offset = index * self.meta.stride;
        return @as(*T, @ptrCast(@alignCast(self.bytes.ptr + offset)));
    }

    pub fn set(self: *ComponentArray, index: usize, value: anytype) !void {
        const T = @TypeOf(value);
        if (self.meta.size == 0 or index >= self.len) return error.IndexOutOfBounds;
        if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;
        const offset = index * self.meta.stride;
        @memcpy(self.bytes[offset .. offset + self.meta.size], std.mem.asBytes(&value));
    }

    pub fn ensureCapacity(self: *ComponentArray, new_capacity: usize) !void {
        if (new_capacity <= self.capacity) return;

        const new_bytes = try self.allocator.alloc(u8, new_capacity * self.meta.stride);
        if (self.capacity > 0) {
            @memcpy(new_bytes[0 .. self.len * self.meta.stride], self.bytes[0 .. self.len * self.meta.stride]);
            self.allocator.free(self.bytes);
        }
        self.bytes = new_bytes;
        self.capacity = new_capacity;
    }

    pub fn ensureTotalCapacity(self: *ComponentArray, new_capacity: usize) !void {
        var better_capacity = self.capacity;
        if (better_capacity >= new_capacity) return;

        while (true) {
            better_capacity +|= better_capacity / 2 + min_occupied_capacity;
            if (better_capacity >= new_capacity) break;
        }
        return self.ensureCapacity(better_capacity);
    }

    pub fn append(self: *ComponentArray, value: anytype) !void {
        try self.ensureTotalCapacity(self.len + 1);
        const T = @TypeOf(value);
        if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;
        const offset = self.len * self.meta.stride;
        @memcpy(self.bytes[offset .. offset + self.meta.size], std.mem.asBytes(&value));
        self.len += 1;
    }

    pub fn insert(self: *ComponentArray, index: usize, value: anytype) !void {
        if (index > self.len) return error.IndexOutOfBounds;

        try self.ensureTotalCapacity(self.len + 1);
        const T = @TypeOf(value);
        if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;

        // Shift elements to the right
        if (index < self.len) {
            const src_offset = index * self.meta.stride;
            const dst_offset = (index + 1) * self.meta.stride;
            const bytes_to_move = (self.len - index) * self.meta.stride;
            std.mem.copyBackwards(u8,
                self.bytes[dst_offset .. dst_offset + bytes_to_move],
                self.bytes[src_offset .. src_offset + bytes_to_move]
            );
        }

        // Insert the new element
        const offset = index * self.meta.stride;
        @memcpy(self.bytes[offset .. offset + self.meta.size], std.mem.asBytes(&value));
        self.len += 1;
    }

    /// `shiftRemove` should be used when order matters. This is not the typical
    /// case in ECS, but it can be useful for certain operations where the order
    /// of components is significant (e.g., rendering order).
    pub fn shiftRemove(self: *ComponentArray, index: usize) void {
        if (index >= self.len) return;

        // Shift elements to the left - use copyBackwards for overlapping memory
        if (index < self.len - 1) {
            const dst_offset = index * self.meta.stride;
            const src_offset = (index + 1) * self.meta.stride;
            const bytes_to_move = (self.len - index - 1) * self.meta.stride;
            std.mem.copyForwards(u8,
                self.bytes[dst_offset .. dst_offset + bytes_to_move],
                self.bytes[src_offset .. src_offset + bytes_to_move]
            );
        }

        self.len -= 1;
    }

    /// `swapRemove` is more efficient for most ECS operations, as it does not
    /// preserve the order of components. It simply replaces the element at `index`
    /// with the last element and reduces the length.
    pub fn swapRemove(self: *ComponentArray, index: usize) void {
        if (index >= self.len) return;

        if (index != self.len - 1) {
            const dst_offset = index * self.meta.stride;
            const src_offset = (self.len - 1) * self.meta.stride;
            @memcpy(
                self.bytes[dst_offset .. dst_offset + self.meta.stride],
                self.bytes[src_offset .. src_offset + self.meta.stride]
            );
        }

        self.len -= 1;
    }

    pub fn clearRetainingCapacity(self: *ComponentArray) void {
        self.len = 0;
    }

    pub fn shrinkAndFree(self: *ComponentArray, new_capacity: usize) !void {
        if (new_capacity >= self.capacity) return;

        const actual_capacity = @max(new_capacity, self.len);
        if (actual_capacity == 0) {
            if (self.bytes.len > 0) {
                self.allocator.free(self.bytes);
                self.bytes = &[_]u8{};
            }
            self.capacity = 0;
            return;
        }

        const new_bytes = try self.allocator.alloc(u8, actual_capacity * self.meta.stride);
        @memcpy(new_bytes[0 .. self.len * self.meta.stride], self.bytes[0 .. self.len * self.meta.stride]);

        if (self.bytes.len > 0) {
            self.allocator.free(self.bytes);
        }

        self.bytes = new_bytes;
        self.capacity = actual_capacity;
    }
};
