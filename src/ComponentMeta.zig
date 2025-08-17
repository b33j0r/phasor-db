const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const componentId = root.componentId;

id: ComponentId,
size: usize,
alignment: u29,
stride: usize,
trait: ?ComponentId,

const ComponentMeta = @This();

pub fn init(id: ComponentId, size: usize, alignment: u29, trait: ?ComponentId) ComponentMeta {
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
    const ComponentT = if (@TypeOf(T) == type) T else @TypeOf(T);

    // check for the __trait__ declaration
    if (@hasDecl(ComponentT, "__trait__")) {
        const trait_id = componentId(ComponentT.__trait__);
        return ComponentMeta.init(
            componentId(ComponentT),
            @sizeOf(ComponentT),
            @alignOf(ComponentT),
            trait_id,
        );
    }

    return ComponentMeta.init(
        componentId(ComponentT),
        @sizeOf(ComponentT),
        @alignOf(ComponentT),
        null,
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