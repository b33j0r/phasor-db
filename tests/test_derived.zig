const std = @import("std");
const testing = std.testing;

const root = @import("phasor-db");
const Database = root.Database;
const Entity = root.Entity;

/// Components
const Position = struct { x: f32 = 0, y: f32 = 0 };
const AttackRange = struct { radius: f32 = 1.0 };
const Target = struct { x: f32 = 0, y: f32 = 0 };

const Health = struct { current: i32 = 100, max: i32 = 100 };

const FloatRect = struct { x: f32, y: f32, w: f32, h: f32 };

/// Derived components
/// (1) HealthRatio
const HealthRatio = struct {
    value: f32,

    pub const __derived__ = struct {
        pub fn derive(entity: Entity) ?HealthRatio {
            const health = entity.get(Health) orelse return null;
            if (health.max <= 0) return null;
            return HealthRatio{
                .value = @as(f32, @floatFromInt(health.current)) /
                    @as(f32, @floatFromInt(health.max)),
            };
        }
    };
};

/// (2) IntRect from FloatRect
const IntRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub const __derived__ = struct {
        pub fn derive(entity: Entity) ?IntRect {
            const fr = entity.get(FloatRect) orelse return null;
            return IntRect{
                .x = @as(i32, @intFromFloat(fr.x)),
                .y = @as(i32, @intFromFloat(fr.y)),
                .w = @as(i32, @intFromFloat(fr.w)),
                .h = @as(i32, @intFromFloat(fr.h)),
            };
        }
    };
};

/// (3) Attackable from Position, AttackRange, Target
const Attackable = struct {
    in_range: bool,

    pub const __derived__ = struct {
        pub fn derive(entity: Entity) ?Attackable {
            const pos = entity.get(Position) orelse return null;
            const range = entity.get(AttackRange) orelse return null;
            const target = entity.get(Target) orelse return null;

            const dx = pos.x - target.x;
            const dy = pos.y - target.y;
            const dist2 = dx * dx + dy * dy;
            const r2 = range.radius * range.radius;

            return Attackable{ .in_range = dist2 <= r2 };
        }
    };
};

fn approxEqual(a: f32, b: f32, eps: f32) bool {
    return @abs(a - b) <= eps;
}

test "Derived components: HealthRatio" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    _ = try db.createEntity(.{Health{ .current = 25, .max = 100 }});
    _ = try db.createEntity(.{Health{ .current = 50, .max = 200 }});

    var q = try db.query(.{HealthRatio});
    defer q.deinit();

    try testing.expectEqual(@as(usize, 2), q.count());

    var it = q.iterator();
    var found: usize = 0;
    while (it.next()) |entity| {
        if (entity.getAlloc(allocator, HealthRatio)) |owned| {
            defer owned.deinit();
            const r = owned.ptr.value;
            found += 1;
            try testing.expect(r >= 0.0 and r <= 1.0);
        }
    }
    try testing.expectEqual(@as(usize, 2), found);
}

test "Derived components: IntRect" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    _ = try db.createEntity(.{FloatRect{ .x = 1.9, .y = 2.1, .w = 3.6, .h = 4.4 }});

    var q = try db.query(.{IntRect});
    defer q.deinit();

    try testing.expectEqual(@as(usize, 1), q.count());

    var it = q.iterator();
    var validated = false;
    while (it.next()) |entity| {
        if (entity.getAlloc(allocator, IntRect)) |owned| {
            defer owned.deinit();
            const r = owned.ptr.*;
            validated = (r.x == 1 and r.y == 2 and r.w == 3 and r.h == 4);
        }
    }
    try testing.expect(validated);
}

test "Derived components: Attackable" {
    const allocator = testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    // In range (dist = 1, radius = 2)
    _ = try db.createEntity(.{
        Position{ .x = 0, .y = 0 },
        AttackRange{ .radius = 2.0 },
        Target{ .x = 1, .y = 0 },
    });

    // Out of range (dist = 5, radius = 2)
    _ = try db.createEntity(.{
        Position{ .x = 0, .y = 0 },
        AttackRange{ .radius = 2.0 },
        Target{ .x = 5, .y = 0 },
    });

    var q = try db.query(.{Attackable});
    defer q.deinit();

    try testing.expectEqual(@as(usize, 2), q.count());

    var it = q.iterator();
    var seen_in = false;
    var seen_out = false;
    while (it.next()) |entity| {
        if (entity.getAlloc(allocator, Attackable)) |owned| {
            defer owned.deinit();
            if (owned.ptr.in_range) {
                seen_in = true;
            } else {
                seen_out = true;
            }
        }
    }

    try testing.expect(seen_in);
    try testing.expect(seen_out);
}
