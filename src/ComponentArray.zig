//! `ComponentArray` is a dynamic type-erased array that holds components of a specific type.
//! It is used to create columns in each `Archetype` table.

const std = @import("std");
const root = @import("root.zig");
const ComponentMeta = root.ComponentMeta;
const ComponentId = root.ComponentId;

allocator: std.mem.Allocator,
meta: ComponentMeta,
capacity: usize = 0,
len: usize = 0,
buffer: AlignedBuffer = .{},

/// Minimum capacity allocated when the array becomes occupied.
pub const min_occupied_capacity = 8;

const ComponentArray = @This();

/// This reduces the frequency of reallocations for small arrays.pub const min_occupied_capacity = 8;
/// Internal buffer structure that manages aligned memory allocation
const AlignedBuffer = struct {
    /// Pointer to the original allocation (for freeing)
    raw_ptr: ?[*]u8 = null,
    /// Length of the original allocation
    raw_len: usize = 0,
    /// Aligned data slice for component storage
    data: []u8 = &[_]u8{},

    fn deinit(self: *AlignedBuffer, allocator: std.mem.Allocator) void {
        if (self.raw_ptr) |ptr| {
            allocator.free(ptr[0..self.raw_len]);
        }
        self.* = .{};
    }

    fn isEmpty(self: *const AlignedBuffer) bool {
        return self.raw_ptr == null and self.data.len == 0;
    }

    fn allocateAligned(
        self: *AlignedBuffer,
        allocator: std.mem.Allocator,
        byte_count: usize,
        alignment: usize,
    ) !void {
        if (byte_count == 0) {
            return;
        }

        const extra = if (alignment > 1) alignment - 1 else 0;
        const raw_allocation = try allocator.alloc(u8, byte_count + extra);

        const raw_addr = @intFromPtr(raw_allocation.ptr);
        const aligned_addr = std.mem.alignForward(usize, raw_addr, alignment);
        const offset = aligned_addr - raw_addr;

        self.raw_ptr = raw_allocation.ptr;
        self.raw_len = raw_allocation.len;
        self.data = raw_allocation[offset .. offset + byte_count];
    }
};

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
    self.buffer.deinit(self.allocator);
    self.* = undefined;
}

pub fn get(self: *const ComponentArray, index: usize, comptime T: type) ?*T {
    if (self.meta.size == 0 or index >= self.len) return null;
    const offset = index * self.meta.stride;
    // Ensure the pointer is properly aligned for type T
    const ptr = self.buffer.data.ptr + offset;
    if (@intFromPtr(ptr) % @alignOf(T) != 0) {
        // Memory is not aligned correctly - this should not happen with proper stride calculation
        return null;
    }
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

pub fn set(self: *ComponentArray, index: usize, value: anytype) !void {
    const T = @TypeOf(value);
    if (self.meta.size == 0 or index >= self.len) return error.IndexOutOfBounds;
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;
    const offset = index * self.meta.stride;
    @memcpy(self.buffer.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
}

pub fn ensureCapacity(self: *ComponentArray, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;

    // If zero-sized component, no backing storage is required
    if (self.meta.stride == 0) {
        self.capacity = new_capacity;
        return;
    }

    const len_bytes: usize = new_capacity * self.meta.stride;
    const alignment: usize = @intCast(self.meta.alignment);

    // Create new aligned buffer
    var new_buffer: AlignedBuffer = .{};
    try new_buffer.allocateAligned(self.allocator, len_bytes, alignment);

    // Copy existing data
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        @memcpy(new_buffer.data[0..copy_len], self.buffer.data[0..copy_len]);
    }

    // Free previous allocation
    self.buffer.deinit(self.allocator);

    self.buffer = new_buffer;
    self.capacity = new_capacity;
}

pub fn ensureTotalCapacity(self: *ComponentArray, new_capacity: usize) !void {
    var better_capacity = self.capacity;
    if (better_capacity >= new_capacity) return;

    // Ensure we start with at least min_occupied_capacity
    if (better_capacity == 0) {
        better_capacity = min_occupied_capacity;
    }

    // Grow capacity until it meets or exceeds new_capacity
    while (better_capacity < new_capacity) {
        better_capacity = better_capacity * 3 / 2 + min_occupied_capacity;
    }
    return self.ensureCapacity(better_capacity);
}

pub fn append(self: *ComponentArray, value: anytype) !void {
    try self.ensureTotalCapacity(self.len + 1);
    const T = @TypeOf(value);
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;
    const offset = self.len * self.meta.stride;
    @memcpy(self.buffer.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
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
        std.mem.copyBackwards(u8, self.buffer.data[dst_offset .. dst_offset + bytes_to_move], self.buffer.data[src_offset .. src_offset + bytes_to_move]);
    }

    // Insert the new element
    const offset = index * self.meta.stride;
    @memcpy(self.buffer.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
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
        std.mem.copyForwards(u8, self.buffer.data[dst_offset .. dst_offset + bytes_to_move], self.buffer.data[src_offset .. src_offset + bytes_to_move]);
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
        @memcpy(self.buffer.data[dst_offset .. dst_offset + self.meta.stride], self.buffer.data[src_offset .. src_offset + self.meta.stride]);
    }

    self.len -= 1;
}

pub fn clearRetainingCapacity(self: *ComponentArray) void {
    self.len = 0;
}

pub fn shrinkAndFree(self: *ComponentArray, new_capacity: usize) !void {
    if (new_capacity >= self.capacity) return;

    const actual_capacity = @max(new_capacity, self.len);
    if (self.meta.stride == 0) {
        self.capacity = actual_capacity;
        return;
    }

    if (actual_capacity == 0) {
        self.buffer.deinit(self.allocator);
        self.buffer = .{};
        self.capacity = 0;
        return;
    }

    const len_bytes: usize = actual_capacity * self.meta.stride;
    const alignment: usize = @intCast(self.meta.alignment);

    // Create new aligned buffer
    var new_buffer: AlignedBuffer = .{};
    try new_buffer.allocateAligned(self.allocator, len_bytes, alignment);

    // Copy existing data
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        @memcpy(new_buffer.data[0..copy_len], self.buffer.data[0..copy_len]);
    }

    // Free previous allocation
    self.buffer.deinit(self.allocator);

    self.buffer = new_buffer;
    self.capacity = actual_capacity;
}
