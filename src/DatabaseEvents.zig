//! `DatabaseEvents` is used by the `Database` to notify
//! subscribers about changes to the database state. It
//! defines the events and their associated data structures.
//!
//! This is created and owned by the `Database`, and is
//! not meant to be instantiated by users.

const std = @import("std");
const root = @import("root.zig");
const Event = root.events.Event;
const Archetype = root.Archetype;
const Entity = root.Entity;

// Events
archetype_added: Event(ArchetypeAdded),

// Event Data Types
pub const ArchetypeAdded = struct {
    archetype: *const Archetype,
};

// Internal Types
const DatabaseEvents = @This();

// Methods
pub fn init(allocator: std.mem.Allocator) DatabaseEvents {
    return DatabaseEvents{
        .archetype_added = Event(ArchetypeAdded).init(allocator),
    };
}

pub fn deinit(self: *DatabaseEvents) void {
    self.archetype_added.deinit();
}
