const std = @import("std");
const root = @import("../root.zig");
const fixtures = @import("fixtures.zig");
const Allocator = std.mem.Allocator;
const Database = root.Database;
const QuerySpec = root.QuerySpec;
const QueryResult = root.QueryResult;
const System = root.System;
const SystemSet = root.SystemSet;
const system = root.system;
const Transaction = root.Transaction;
const Entity = root.Entity;
const testing = std.testing;

const DeltaTime = struct {
    seconds: f32,
};

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};
