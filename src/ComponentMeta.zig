const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const componentId = root.componentId;
const Trait = root.Trait;

id: ComponentId,
size: usize,
alignment: u29,
stride: usize,
trait: ?Trait,

const ComponentMeta = @This();

pub fn init(id: ComponentId, size: usize, alignment: u29, trait: ?Trait) ComponentMeta {
    const stride = if (size == 0) 0 else std.mem.alignForward(usize, size, alignment);
    return ComponentMeta{
        .id = id,
        .size = size,
        .alignment = alignment,
        .stride = stride,
        .trait = trait,
    };
}

pub fn from(comptime T: anytype) ComponentMeta {
    // This can be used with a type or a value.
    const ComponentT = switch (@TypeOf(T)) {
        type => T,
        else => @TypeOf(T),
    };
    const trait = Trait.maybeFrom(ComponentT);
    return ComponentMeta.init(
        componentId(ComponentT),
        @sizeOf(ComponentT),
        @alignOf(ComponentT),
        trait,
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
