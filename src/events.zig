const std = @import("std");

pub fn Event(comptime E: type) type {
    return struct {
        pub fn init() Event(E) {
            return Event(E){};
        }
    };
}
