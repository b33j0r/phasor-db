//! `Drop` supports components with `deinit` methods. They are called when:
//!
//! - An entity is destroyed
//! - A component is removed from an entity
//! - A component is replaced on an entity
//!
//! `Drop` is tracked in the ComponentMeta for a component type.

drop_fn: DropFn,

const DropFn = struct {
    fn_ptr: ?*const fn (*anyopaque) void = null,

    pub fn from(comptime T: anytype) DropFn {
        std.debug.assert(@hasDecl(T, "deinit"));

        if (@typeInfo(@TypeOf(T.deinit)) == .@"fn") {
            const Thunk = struct {
                fn call(instance: *anyopaque) void {
                    const typed: *T = @ptrCast(@alignCast(instance));
                    T.deinit(typed);
                }
            };
            return .{ .fn_ptr = Thunk.call };
        }

        @compileError(@typeName(T) ++ ".deinit must be a function");
    }

    pub fn call(self: DropFn, ptr: *anyopaque) void {
        if (self.fn_ptr) |f| f(ptr);
    }
};

const Drop = @This();

pub fn maybeFrom(comptime T: anytype) ?Drop {
    if (@hasDecl(T, "deinit")) {
        return Drop{
            .drop_fn = DropFn.from(T),
        };
    } else {
        return null;
    }
}

// ------
// Imports
// ------

const std = @import("std");

const root = @import("root.zig");
const ComponentMeta = root.ComponentMeta;
const ComponentId = root.ComponentId;
