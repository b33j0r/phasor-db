//! `ComponentArray` is a dynamic type-erased array that holds components of a specific type.
//! It is used to create columns in each `Archetype` table.

const std = @import("std");
const root = @import("root.zig");
const ComponentMeta = root.ComponentMeta;
const ComponentId = root.ComponentId;

const ComponentArray = @This();

allocator: std.mem.Allocator,
meta: ComponentMeta,
capacity: usize = 0,
len: usize = 0,
buffer: Buffer = .{},

/// Minimum capacity allocated when the array becomes occupied.
pub const min_occupied_capacity = 8;

/// Internal buffer that requests aligned memory directly from the allocator.
const Buffer = struct {
    ptr: ?[*]u8 = null,
    len: usize = 0,
    alignment: u29 = 1, // byte units

    fn isEmpty(self: *const Buffer) bool {
        return self.ptr == null or self.len == 0;
    }

    fn asSlice(self: *const Buffer) []u8 {
        if (self.ptr) |p| return p[0..self.len];
        return &[_]u8{};
    }

    fn alloc(self: *Buffer, allocator: std.mem.Allocator, n: usize, alignment: u29) !void {
        if (n == 0) {
            self.* = .{};
            return;
        }
        const a: std.mem.Alignment = std.mem.Alignment.fromByteUnits(@intCast(alignment));
        const p = allocator.rawAlloc(n, a, @returnAddress()) orelse return error.OutOfMemory;
        self.ptr = p;
        self.len = n;
        self.alignment = alignment;
    }

    fn free(self: *Buffer, allocator: std.mem.Allocator) void {
        if (self.ptr) |p| {
            const a: std.mem.Alignment = std.mem.Alignment.fromByteUnits(@intCast(self.alignment));
            // rawFree expects a slice in 0.15
            allocator.rawFree(p[0..self.len], a, @returnAddress());
        }
        self.* = .{};
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

/// Construct from either a type *or* a value.
/// If given a value, the array is created and the value is appended.
pub fn from(
    allocator: std.mem.Allocator,
    comptime T: anytype,
) !ComponentArray {
    const is_value = @TypeOf(T) != type;
    const ComponentT = if (is_value) @TypeOf(T) else T;

    const meta = ComponentMeta.from(ComponentT);
    var component_array = ComponentArray.init(allocator, meta);
    if (is_value) {
        try component_array.append(T);
    }
    return component_array;
}

pub fn deinit(self: *ComponentArray) void {
    self.buffer.free(self.allocator);
    self.* = undefined;
}

pub fn get(self: *const ComponentArray, index: usize, comptime T: type) ?*T {
    if (self.meta.size == 0 or index >= self.len) return null;

    // Invariant: base allocation is meta.alignment-aligned and stride respects alignment.
    const offset = index * self.meta.stride;
    const base = self.buffer.asSlice();
    const ptr = base.ptr + offset;

    // Keep in debug/safe; omit in ReleaseFast if you like.
    std.debug.assert(@intFromPtr(ptr) % @alignOf(T) == 0);

    return @as(*T, @ptrCast(@alignCast(ptr)));
}

pub fn set(self: *ComponentArray, index: usize, value: anytype) !void {
    const T = @TypeOf(value);
    if (self.meta.size == 0 or index >= self.len) return error.IndexOutOfBounds;
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;

    const offset = index * self.meta.stride;
    const base = self.buffer.asSlice();
    @memcpy(base[offset .. offset + self.meta.size], std.mem.asBytes(&value));
}

pub fn ensureCapacity(self: *ComponentArray, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;

    // ZSTs need no backing storage but still track capacity for len bounds.
    if (self.meta.stride == 0) {
        self.capacity = new_capacity;
        return;
    }

    const len_bytes: usize = new_capacity * self.meta.stride;

    var new_buffer: Buffer = .{};
    try new_buffer.alloc(self.allocator, len_bytes, self.meta.alignment);

    // Copy existing data.
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        const dst = new_buffer.asSlice();
        const src = self.buffer.asSlice();
        @memcpy(dst[0..copy_len], src[0..copy_len]);
    }

    // Free previous allocation and install new.
    self.buffer.free(self.allocator);
    self.buffer = new_buffer;
    self.capacity = new_capacity;
}

pub fn ensureTotalCapacity(self: *ComponentArray, new_capacity: usize) !void {
    if (self.capacity >= new_capacity) return;

    const better_capacity = @max(
        self.capacity * 3 / 2,
        @max(new_capacity, min_occupied_capacity),
    );

    return self.ensureCapacity(better_capacity);
}

pub fn append(self: *ComponentArray, value: anytype) !void {
    // ZST fast-path: just bump len and maybe capacity bookkeeping.
    if (self.meta.stride == 0) {
        try self.ensureTotalCapacity(self.len + 1);
        self.len += 1;
        return;
    }

    try self.ensureTotalCapacity(self.len + 1);

    const T = @TypeOf(value);
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;

    const offset = self.len * self.meta.stride;
    const base = self.buffer.asSlice();
    @memcpy(base[offset .. offset + self.meta.size], std.mem.asBytes(&value));

    self.len += 1;
}

pub fn insert(self: *ComponentArray, index: usize, value: anytype) !void {
    if (index > self.len) return error.IndexOutOfBounds;

    // ZST fast-path: no bytes, only indices move logically.
    if (self.meta.stride == 0) {
        try self.ensureTotalCapacity(self.len + 1);
        // For ZSTs, "shifting" is a no-op on storage; we just increment len.
        self.len += 1;
        return;
    }

    try self.ensureTotalCapacity(self.len + 1);

    const T = @TypeOf(value);
    if (@sizeOf(T) != self.meta.size) return error.TypeMismatch;

    // Shift elements to the right. Because dst > src (overlapping), use copyBackwards.
    if (index < self.len) {
        const src_offset = index * self.meta.stride;
        const dst_offset = (index + 1) * self.meta.stride;
        const bytes_to_move = (self.len - index) * self.meta.stride;

        const base = self.buffer.asSlice();
        std.mem.copyBackwards(
            u8,
            base[dst_offset .. dst_offset + bytes_to_move],
            base[src_offset .. src_offset + bytes_to_move],
        );
    }

    // Insert the new element.
    const offset = index * self.meta.stride;
    const base = self.buffer.asSlice();
    @memcpy(base[offset .. offset + self.meta.size], std.mem.asBytes(&value));

    self.len += 1;
}

/// `shiftRemove` should be used when order matters (e.g., rendering order).
/// Shifts elements left. Since dst < src here, `copyForwards` is correct for the overlap.
pub fn shiftRemove(self: *ComponentArray, index: usize) void {
    if (index >= self.len) return;

    if (self.meta.stride != 0 and index < self.len - 1) {
        const dst_offset = index * self.meta.stride;
        const src_offset = (index + 1) * self.meta.stride;
        const bytes_to_move = (self.len - index - 1) * self.meta.stride;

        const base = self.buffer.asSlice();
        std.mem.copyForwards(
            u8,
            base[dst_offset .. dst_offset + bytes_to_move],
            base[src_offset .. src_offset + bytes_to_move],
        );
    }

    self.len -= 1;
}

/// `swapRemove` is more efficient when order does not matter.
/// Replaces the removed element with the last element.
pub fn swapRemove(self: *ComponentArray, index: usize) void {
    if (index >= self.len) return;

    if (self.meta.stride != 0 and index != self.len - 1) {
        const dst_offset = index * self.meta.stride;
        const src_offset = (self.len - 1) * self.meta.stride;

        const base = self.buffer.asSlice();
        @memcpy(
            base[dst_offset .. dst_offset + self.meta.stride],
            base[src_offset .. src_offset + self.meta.stride],
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

    if (self.meta.stride == 0) {
        self.capacity = actual_capacity;
        if (actual_capacity == 0) {
            self.buffer.free(self.allocator);
            self.buffer = .{};
        }
        return;
    }

    if (actual_capacity == 0) {
        self.buffer.free(self.allocator);
        self.buffer = .{};
        self.capacity = 0;
        return;
    }

    const len_bytes: usize = actual_capacity * self.meta.stride;

    var new_buffer: Buffer = .{};
    try new_buffer.alloc(self.allocator, len_bytes, self.meta.alignment);

    // Copy existing data up to current len.
    const copy_len = self.len * self.meta.stride;
    if (copy_len > 0) {
        const dst = new_buffer.asSlice();
        const src = self.buffer.asSlice();
        @memcpy(dst[0..copy_len], src[0..copy_len]);
    }

    self.buffer.free(self.allocator);
    self.buffer = new_buffer;
    self.capacity = actual_capacity;
}
