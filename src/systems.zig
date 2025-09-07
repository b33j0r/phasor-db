const std = @import("std");
const root = @import("root.zig");
const Transaction = root.Transaction;
const QueryResult = root.QueryResult;
const QuerySpec = root.QuerySpec;

pub fn Res(comptime T: type) type {
    return struct {
        value: *T,
        pub fn init(tx: Transaction) !@This() {
            return .{ .value = tx.getResource(T).? };
        }
    };
}

pub fn Query(comptime Components: anytype) type {
    return struct {
        query: QuerySpec(Components),
        pub fn init(tx: Transaction) !@This() {
            return .{ .query = try tx.query(Components) };
        }
    };
}

pub fn SystemParam(comptime T: type) type {
    return switch (T) {
        Transaction => struct {
            pub fn init(tx: Transaction) Transaction {
                return tx;
            }
        },
        else => if (@hasDecl(T, "init")) T else struct {
            pub fn init(_: Transaction) !T {
                @compileError("Unsupported system param: " ++ @typeName(T));
            }
        },
    };
}

pub fn system(comptime F: anytype) type {
    const info = @typeInfo(@TypeOf(F)).@"fn";
    return struct {
        pub fn run(tx: Transaction) !void {
            var args: std.meta.ArgsTuple(@TypeOf(F)) = undefined;

            inline for (info.params, 0..) |param, i| {
                const T = param.type.?;
                args[i] = try SystemParam(T).init(tx);
            }

            @call(.auto, F, args);
        }
    };
}

pub const System = struct {};

pub const SystemSet = struct {
    allocator: std.mem.Allocator,
    systems: std.ArrayListUnmanaged(System) = .empty,

    pub fn init(allocator: std.mem.Allocator) SystemSet {
        return SystemSet{
            .allocator = allocator,
        };
    }

    pub fn add(comptime S: type, self: *SystemSet) !void {
        try self.systems.append(self.allocator, System(S));
    }

    pub fn deinit(self: *SystemSet) void {
        self.systems.deinit(self.allocator);
    }
};
