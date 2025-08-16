//! `Transaction` is a command queue that can be used
//! to execute a series of commands in a single transaction.
//! It is a facade over the `Database` and provides a way to
//! batch operations on entities and components.

const std = @import("std");
const root = @import("root.zig");
const Entity = root.Entity;
const ComponentId = root.ComponentId;
const Database = root.Database;

pub const Command = struct {

};