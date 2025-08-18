//! `Event` is a simple pubsub (publish-subscribe) event system
//! that works with callbacks. A type can define Event(T) fields
//! like `on_something_happened: Event(SomethingHappenedEvent)`,
//! and then subscribers can register callbacks to be notified
//! when events of type `SomethingHappenedEvent` are published.

const std = @import("std");

pub fn Event(comptime E: type) type {
    return struct {
        const Callback = *const fn (context: *anyopaque, evt: *const E) void;

        const Subscriber = struct {
            context: *anyopaque,
            callback: Callback,
        };

        const Self = @This();

        allocator: std.mem.Allocator,
        subscribers: std.ArrayListUnmanaged(Subscriber) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn subscribe(self: *Self, context: *anyopaque, cb: Callback) !void {
            try self.subscribers.append(self.allocator, .{ .context = context, .callback = cb });
        }

        pub fn publish(self: *Self, evt: *const E) void {
            for (self.subscribers.items) |s| {
                s.callback(s.context, evt);
            }
        }

        pub fn deinit(self: *Self) void {
            self.subscribers.deinit(self.allocator);
        }
    };
}

test "Event with one subscriber" {
    const E = struct { data: u32 };

    const MySubscriber = struct {
        data: u32 = 0,

        const Self = @This();

        pub fn onEvent(context: *anyopaque, evt: *const E) void {
            const self = @as(*Self, @alignCast(@ptrCast(context)));
            self.data += evt.data;
        }
    };

    var my_subscriber = MySubscriber{ .data = 0 };

    const allocator = std.testing.allocator;
    var publisher = Event(E).init(allocator);
    defer publisher.deinit();

    try publisher.subscribe(&my_subscriber, MySubscriber.onEvent);
    const event = E{ .data = 42 };
    publisher.publish(&event);

    try std.testing.expectEqual(42, my_subscriber.data);
}

test "Event with two subscribers" {
    const E = struct { data: u32 };

    const SubscriberA = struct {
        data: u32 = 0,

        const Self = @This();

        pub fn onEvent(context: *anyopaque, evt: *const E) void {
            const self = @as(*Self, @alignCast(@ptrCast(context)));
            self.data += evt.data;
        }
    };

    const SubscriberB = struct {
        data: u32 = 0,

        const Self = @This();

        pub fn onEvent(context: *anyopaque, evt: *const E) void {
            const self = @as(*Self, @alignCast(@ptrCast(context)));
            self.data += evt.data * 2; // Different processing
        }
    };

    var sub_a = SubscriberA{ .data = 0 };
    var sub_b = SubscriberB{ .data = 0 };

    const allocator = std.testing.allocator;
    var publisher = Event(E).init(allocator);
    defer publisher.deinit();

    try publisher.subscribe(&sub_a, SubscriberA.onEvent);
    try publisher.subscribe(&sub_b, SubscriberB.onEvent);

    const event = E{ .data = 21 };
    publisher.publish(&event);

    try std.testing.expectEqual(21, sub_a.data);
    try std.testing.expectEqual(42, sub_b.data);
}
