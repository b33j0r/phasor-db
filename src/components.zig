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

/// `ComponentArray` is a dynamic type-erased array that holds components of a specific type.
/// It is used to create columns in each `Archetype` table.
pub const ComponentArray = struct {
    allocator: std.mem.Allocator,
    id: ComponentId,
    size: usize,
    alignment: u29,
    stride: usize,
    capacity: usize = 0,
    len: usize = 0,
    bytes: []u8 = &[_]u8{},

    /// Minimum capacity allocated when the array becomes occupied.
    /// This reduces the frequency of reallocations for small arrays.
    pub const min_occupied_capacity = 8;

    pub fn init(
        allocator: std.mem.Allocator,
        id: ComponentId,
        size: usize,
        alignment: u29,
    ) ComponentArray {
        const stride = if (size == 0) 0 else std.mem.alignForward(usize, size, alignment);
        return ComponentArray{
            .allocator = allocator,
            .id = id,
            .size = size,
            .alignment = alignment,
            .stride = stride,
        };
    }

    pub fn from(
        allocator: std.mem.Allocator,
        comptime T: anytype,
    ) !ComponentArray {
        const hasValue = @TypeOf(T) != type;
        const ComponentT = if (hasValue) @TypeOf(T) else T;
        var component_array = ComponentArray.init(
            allocator,
            componentId(ComponentT),
            @sizeOf(ComponentT),
            @alignOf(ComponentT),
        );
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
        if (self.size == 0 or index >= self.len) return null;
        const offset = index * self.stride;
        return @as(*T, @ptrCast(@alignCast(self.bytes.ptr + offset)));
    }

    pub fn set(self: *ComponentArray, index: usize, value: anytype) !void {
        const T = @TypeOf(value);
        if (self.size == 0 or index >= self.len) return error.IndexOutOfBounds;
        if (@sizeOf(T) != self.size) return error.TypeMismatch;
        const offset = index * self.stride;
        @memcpy(self.bytes[offset .. offset + self.size], std.mem.asBytes(&value));
    }

    pub fn ensureCapacity(self: *ComponentArray, new_capacity: usize) !void {
        if (new_capacity <= self.capacity) return;

        const new_bytes = try self.allocator.alloc(u8, new_capacity * self.stride);
        if (self.capacity > 0) {
            @memcpy(new_bytes[0 .. self.len * self.stride], self.bytes[0 .. self.len * self.stride]);
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
        if (@sizeOf(T) != self.size) return error.TypeMismatch;
        const offset = self.len * self.stride;
        @memcpy(self.bytes[offset .. offset + self.size], std.mem.asBytes(&value));
        self.len += 1;
    }

    pub fn insert(self: *ComponentArray, index: usize, value: anytype) !void {
        if (index > self.len) return error.IndexOutOfBounds;

        try self.ensureTotalCapacity(self.len + 1);
        const T = @TypeOf(value);
        if (@sizeOf(T) != self.size) return error.TypeMismatch;

        // Shift elements to the right
        if (index < self.len) {
            const src_offset = index * self.stride;
            const dst_offset = (index + 1) * self.stride;
            const bytes_to_move = (self.len - index) * self.stride;
            std.mem.copyBackwards(u8,
                self.bytes[dst_offset .. dst_offset + bytes_to_move],
                self.bytes[src_offset .. src_offset + bytes_to_move]
            );
        }

        // Insert the new element
        const offset = index * self.stride;
        @memcpy(self.bytes[offset .. offset + self.size], std.mem.asBytes(&value));
        self.len += 1;
    }

    /// `shiftRemove` should be used when order matters. This is not the typical
    /// case in ECS, but it can be useful for certain operations where the order
    /// of components is significant (e.g., rendering order).
    pub fn shiftRemove(self: *ComponentArray, index: usize) void {
        if (index >= self.len) return;

        // Shift elements to the left - use copyBackwards for overlapping memory
        if (index < self.len - 1) {
            const dst_offset = index * self.stride;
            const src_offset = (index + 1) * self.stride;
            const bytes_to_move = (self.len - index - 1) * self.stride;
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
            const dst_offset = index * self.stride;
            const src_offset = (self.len - 1) * self.stride;
            @memcpy(
                self.bytes[dst_offset .. dst_offset + self.stride],
                self.bytes[src_offset .. src_offset + self.stride]
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

        const new_bytes = try self.allocator.alloc(u8, actual_capacity * self.stride);
        @memcpy(new_bytes[0 .. self.len * self.stride], self.bytes[0 .. self.len * self.stride]);

        if (self.bytes.len > 0) {
            self.allocator.free(self.bytes);
        }

        self.bytes = new_bytes;
        self.capacity = actual_capacity;
    }
};
