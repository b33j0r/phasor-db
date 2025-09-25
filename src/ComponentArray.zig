//! `ComponentArray` is a dynamic type-erased array that holds components of a specific type.
//! It is used to create columns in each `Archetype` table.

const std = @import("std");
const root = @import("root.zig");
const ComponentMeta = root.ComponentMeta;
const ComponentId = root.ComponentId;
const Trait = root.Trait;
const Drop = root.Drop;

allocator: std.mem.Allocator,
meta: ComponentMeta,
capacity: usize = 0,
len: usize = 0,
data: []u8 = &[_]u8{},

/// Minimum capacity allocated when the array becomes occupied.
pub const min_occupied_capacity = 8;

const ComponentArray = @This();

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
    trait: ?Trait,
    drop: ?Drop,
) ComponentArray {
    const meta = ComponentMeta.init(id, size, alignment, trait, drop);
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
    self.dropRange(0, self.len);

    if (self.data.len > 0) {
        const alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);
        self.allocator.rawFree(self.data, alignment, @returnAddress());
    }
    self.* = undefined;
}

pub fn get(self: *const ComponentArray, index: usize, comptime T: type) ?*T {
    if (index >= self.len) return null;

    if (@sizeOf(T) == 0) {
        // For ZSTs, return a pointer to a global constant
        const global_zst: T = .{};
        return @as(*T, @ptrFromInt(@intFromPtr(&global_zst)));
    }

    const offset = index * self.meta.stride;
    // Ensure the pointer is properly aligned for type T
    const ptr = self.data.ptr + offset;
    std.debug.assert(@intFromPtr(ptr) % @alignOf(T) == 0);
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

pub fn set(self: *ComponentArray, index: usize, value: anytype) !void {
    const T = @TypeOf(value);
    if (index >= self.len) return error.IndexOutOfBounds;
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;

    // For zero-sized components, no memory operation is needed
    if (self.meta.size == 0) return;

    self.dropAt(index);

    const offset = index * self.meta.stride;
    @memcpy(self.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
}

pub fn ensureCapacity(self: *ComponentArray, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;

    // If zero-sized component, no backing storage is required
    if (self.meta.stride == 0) {
        self.capacity = new_capacity;
        return;
    }

    const len_bytes: usize = new_capacity * self.meta.stride;
    const alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);

    // Allocate new aligned memory using standard allocator
    const raw_ptr = self.allocator.rawAlloc(len_bytes, alignment, @returnAddress()) orelse return error.OutOfMemory;
    const new_data = raw_ptr[0..len_bytes];

    // Copy existing data
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        @memcpy(new_data[0..copy_len], self.data[0..copy_len]);
    }

    // Free previous allocation
    if (self.data.len > 0) {
        const old_alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);
        self.allocator.rawFree(self.data, old_alignment, @returnAddress());
    }

    self.data = new_data;
    self.capacity = new_capacity;
}

pub fn ensureTotalCapacity(self: *ComponentArray, new_capacity: usize) !void {
    if (self.capacity >= new_capacity) return;

    const better_capacity = @max(self.capacity * 3 / 2, @max(new_capacity, min_occupied_capacity));

    return self.ensureCapacity(better_capacity);
}

pub fn append(self: *ComponentArray, value: anytype) !void {
    try self.ensureTotalCapacity(self.len + 1);
    const T = @TypeOf(value);
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;
    const offset = self.len * self.meta.stride;
    @memcpy(self.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
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
        std.mem.copyBackwards(u8, self.data[dst_offset .. dst_offset + bytes_to_move], self.data[src_offset .. src_offset + bytes_to_move]);
    }

    // Insert the new element
    const offset = index * self.meta.stride;
    @memcpy(self.data[offset .. offset + self.meta.size], std.mem.asBytes(&value));
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
        std.mem.copyForwards(u8, self.data[dst_offset .. dst_offset + bytes_to_move], self.data[src_offset .. src_offset + bytes_to_move]);
    }

    self.len -= 1;
}

/// `swapRemove` is more efficient for most ECS operations, as it does not
/// preserve the order of components. It simply replaces the element at `index`
/// with the last element and reduces the length.
pub fn swapRemove(self: *ComponentArray, index: usize) void {
    if (index >= self.len) return;

    self.dropAt(index);

    if (index != self.len - 1) {
        const dst_offset = index * self.meta.stride;
        const src_offset = (self.len - 1) * self.meta.stride;
        @memcpy(self.data[dst_offset .. dst_offset + self.meta.stride], self.data[src_offset .. src_offset + self.meta.stride]);
    }

    self.len -= 1;
}

pub fn clearRetainingCapacity(self: *ComponentArray) void {
    self.dropRange(0, self.len);
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
        if (self.data.len > 0) {
            const alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);
            self.allocator.rawFree(self.data, alignment, @returnAddress());
        }
        self.data = &[_]u8{};
        self.capacity = 0;
        return;
    }

    const len_bytes: usize = actual_capacity * self.meta.stride;
    const alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);

    // Allocate new aligned memory using standard allocator
    const raw_ptr = self.allocator.rawAlloc(len_bytes, alignment, @returnAddress()) orelse return error.OutOfMemory;
    const new_data = raw_ptr[0..len_bytes];

    // Copy existing data
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        @memcpy(new_data[0..copy_len], self.data[0..copy_len]);
    }

    // Free previous allocation
    if (self.data.len > 0) {
        const old_alignment = std.mem.Alignment.fromByteUnits(self.meta.alignment);
        self.allocator.rawFree(self.data, old_alignment, @returnAddress());
    }

    self.data = new_data;
    self.capacity = actual_capacity;
}

/// Copies an element from this ComponentArray to the end of another ComponentArray.
/// Both arrays must have the same component type (same meta.id and meta.size).
/// The destination array will be expanded to accommodate the new element.
pub fn copyElementToEnd(
    self: *const ComponentArray,
    src_index: usize,
    dest_array: *ComponentArray,
) !void {
    if (src_index >= self.len) return error.IndexOutOfBounds;
    if (self.meta.id != dest_array.meta.id) return error.ComponentTypeMismatch;
    if (self.meta.size != dest_array.meta.size) return error.ComponentSizeMismatch;

    // Ensure destination has capacity for one more element
    try dest_array.ensureTotalCapacity(dest_array.len + 1);

    // Zero-sized components are a no-op, but we still increment the length at the end
    if (self.meta.size != 0) {
        const src_offset = src_index * self.meta.stride;
        const dest_offset = dest_array.len * dest_array.meta.stride;

        @memcpy(dest_array.data[dest_offset .. dest_offset + self.meta.size], self.data[src_offset .. src_offset + self.meta.size]);
    }

    dest_array.len += 1;
}

fn dropAt(self: *ComponentArray, index: usize) void {
    if (index >= self.len) return;
    if (self.meta.stride == 0) return;
    const drop = self.meta.drop orelse return;

    const offset = index * self.meta.stride;
    const any_ptr: *anyopaque = @ptrFromInt(@intFromPtr(self.data.ptr) + offset);
    drop.drop_fn.call(any_ptr);
}

fn dropRange(self: *ComponentArray, start: usize, end: usize) void {
    if (self.meta.stride == 0) return;
    const drop = self.meta.drop orelse return;

    var i = start;
    while (i < end and i < self.len) : (i += 1) {
        const offset = i * self.meta.stride;
        const any_ptr: *anyopaque = @ptrFromInt(@intFromPtr(self.data.ptr) + offset);
        drop.drop_fn.call(any_ptr);
    }
}