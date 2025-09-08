const std = @import("std");
const root = @import("root.zig");
const Transaction = root.Transaction;

/// A system is a type-erased function that can be scheduled.
pub const System = struct {
    run: *const fn (transaction: *Transaction) anyerror!void,

    pub fn from(comptime system_fn: anytype) !System {
        // Validate that system_fn is a function
        const fn_type = @TypeOf(system_fn);
        const type_info = @typeInfo(fn_type);
        if (type_info != .@"fn") {
            return error.InvalidSystemFunction;
        }

        if (type_info.@"fn".params.len == 0) {
            return error.SystemMustHaveParameters;
        }

        const runFn = &struct {
            pub fn run(transaction: *Transaction) !void {
                // Make an arg tuple type for the system function
                const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(system_fn));
                var args_tuple: ArgsTupleType = undefined;

                // Fill in the args tuple based on parameter types
                inline for (std.meta.fields(ArgsTupleType), 0..) |field, i| {
                    const ParamType = field.type;

                    // Check if this is a Transaction parameter
                    if (ParamType == *Transaction) {
                        // Get transaction from database
                        args_tuple[i] = transaction;
                    } else if (@hasDecl(ParamType, "init_system_param")) {
                        // It's a system parameter (e.g., Res(T))
                        var param_instance: ParamType = undefined;
                        try param_instance.init_system_param(transaction);
                        args_tuple[i] = param_instance;
                    } else {
                        @compileError("Unsupported system parameter type: " ++ @typeName(ParamType));
                    }
                }

                // Call the original system function with the prepared arguments
                return @call(.auto, system_fn, args_tuple);
            }
        }.run;

        return System{ .run = runFn };
    }
};

// System Parameters
//
// System parameters are used to determine the dependency
// graph of systems. They are specified as comptime wrappers.

/// `Res(T)` is a comptime wrapper to specify
/// a resource of type `T` as a system parameter.
pub fn Res(comptime ResourceT: type) type {
    return struct {
        ptr: *T,

        const Self = @This();
        pub const T = ResourceT;

        pub fn init_system_param(self: *Self, tx: *Transaction) !void {
            self.ptr = tx.getResource(ResourceT).?;
        }
    };
}

/// `Query` is a declarative comptime construct to specify
/// a query for components in the ECS database.
///
/// When used as a system parameter, it is a wrapper that fetches a QueryResult
/// from the Transaction during system parameter initialization.
pub fn Query(comptime Parts: anytype) type {
    const QueryResult = root.QueryResult;
    const Entity = root.Entity;
    return struct {
        result: QueryResult = undefined,

        const Self = @This();

        /// Initializes this system parameter by executing the query on the transaction.
        pub fn init_system_param(self: *Self, tx: *root.Transaction) !void {
            self.result = try tx.query(Parts);
        }

        /// Free resources held by the underlying QueryResult.
        pub fn deinit(self: *Self) void {
            self.result.deinit();
        }

        /// Number of entities matching the query.
        pub fn count(self: *const Self) usize {
            return self.result.count();
        }

        /// Iterator over entities matching the query.
        pub fn iterator(self: *const Self) QueryResult.Iterator {
            return self.result.iterator();
        }

        /// Convenience to get the first entity matching the query, if any.
        pub fn first(self: *const Self) ?Entity {
            return self.result.first();
        }

        /// Group the results by a trait.
        pub fn groupBy(self: *const Self, TraitT: anytype) !root.GroupByResult {
            return self.result.groupBy(TraitT);
        }
    };
}

/// A marker to specify that a component is mutable
/// in a query result.
pub fn Mut(comptime ComponentT: type) type {
    return ComponentT;
}

/// A marker to specify that a component is NOT present
/// in a query result.
pub fn Without(comptime ComponentT: type) type {
    return ComponentT;
}

/// A marker to specify grouping in a query result.
pub fn GroupBy(comptime ComponentT: type) type {
    return ComponentT;
}
