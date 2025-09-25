drop_fn: DropFn,

const DropFn = struct {
    fn_ptr: ?*const fn (*anyopaque) void = null,

    pub fn from(comptime T: anytype) DropFn {
        std.debug.assert(@hasDecl(T, "__drop__"));

        if (@typeInfo(@TypeOf(T.__drop__)) == .@"fn") {
            const Thunk = struct {
                fn call(instance: *anyopaque) void {
                    const typed: *T = @ptrCast(@alignCast(instance));
                    T.__drop__(typed);
                }
            };
            return .{ .fn_ptr = Thunk.call };
        }

        @compileError(@typeName(T) ++ ".__drop__ must be a function");
    }

    pub fn call(self: DropFn, ptr: *anyopaque) void {
        if (self.fn_ptr) |f| f(ptr);
    }
};

const Drop = @This();

pub fn maybeFrom(comptime T: anytype) ?Drop {
    if (@hasDecl(T, "__drop__")) {
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