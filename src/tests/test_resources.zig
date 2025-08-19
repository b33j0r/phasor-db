const std = @import("std");
const testing = std.testing;
const root = @import("../root.zig");
const ResourceManager = root.ResourceManager;
const Database = root.Database;
const resourceId = ResourceManager.resourceId;

// Test resource types
const ClearColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const WindowSize = struct {
    width: u32,
    height: u32,
};

const GameConfig = struct {
    max_players: u32,
    level_count: u32,
    title: []const u8,
};

const PlayerStats = struct {
    score: i64,
    level: u32,
    lives: i32,
};

// Zero-sized type for testing
const GameMarker = struct {};

// Large resource type for testing memory management
const LargeResource = struct {
    data: [1024]u8,
    
    fn init() LargeResource {
        return LargeResource{
            .data = [_]u8{0} ** 1024,
        };
    }
};

test "ResourceManager basic initialization and deinitialization" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();
    
    // Manager should be empty initially
    try testing.expect(!manager.has(ClearColor));
    try testing.expect(!manager.has(WindowSize));
}

test "ResourceManager insert and get operations" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert a ClearColor resource
    const clear_color = ClearColor{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 };
    try manager.insert(clear_color);

    // Get it back and verify values
    const retrieved_color = manager.get(ClearColor).?;
    try testing.expectEqual(@as(f32, 1.0), retrieved_color.r);
    try testing.expectEqual(@as(f32, 0.5), retrieved_color.g);
    try testing.expectEqual(@as(f32, 0.0), retrieved_color.b);
    try testing.expectEqual(@as(f32, 1.0), retrieved_color.a);
}

test "ResourceManager has operation" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Initially should not have any resources
    try testing.expect(!manager.has(ClearColor));
    try testing.expect(!manager.has(WindowSize));

    // Add a resource
    try manager.insert(ClearColor{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 });

    // Now should have ClearColor but not WindowSize
    try testing.expect(manager.has(ClearColor));
    try testing.expect(!manager.has(WindowSize));
}

test "ResourceManager replace existing resource" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert initial resource
    try manager.insert(ClearColor{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 });
    
    // Verify initial values
    const initial_color = manager.get(ClearColor).?;
    try testing.expectEqual(@as(f32, 1.0), initial_color.r);
    try testing.expectEqual(@as(f32, 0.5), initial_color.g);

    // Replace with new value
    try manager.insert(ClearColor{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 });

    // Verify new values
    const new_color = manager.get(ClearColor).?;
    try testing.expectEqual(@as(f32, 0.0), new_color.r);
    try testing.expectEqual(@as(f32, 1.0), new_color.g);
    try testing.expectEqual(@as(f32, 0.0), new_color.b);
    try testing.expectEqual(@as(f32, 1.0), new_color.a);
}

test "ResourceManager multiple resource types" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Add different resource types
    try manager.insert(ClearColor{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 });
    try manager.insert(WindowSize{ .width = 1920, .height = 1080 });

    // Verify both exist
    try testing.expect(manager.has(ClearColor));
    try testing.expect(manager.has(WindowSize));

    // Verify values
    const color = manager.get(ClearColor).?;
    try testing.expectEqual(@as(f32, 1.0), color.r);
    try testing.expectEqual(@as(f32, 0.0), color.g);

    const size = manager.get(WindowSize).?;
    try testing.expectEqual(@as(u32, 1920), size.width);
    try testing.expectEqual(@as(u32, 1080), size.height);
}

test "ResourceManager remove operation" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Add resources
    try manager.insert(ClearColor{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 });
    try manager.insert(WindowSize{ .width = 800, .height = 600 });

    // Verify both exist
    try testing.expect(manager.has(ClearColor));
    try testing.expect(manager.has(WindowSize));

    // Remove ClearColor
    const removed = manager.remove(ClearColor);
    try testing.expect(removed);

    // Verify ClearColor is gone but WindowSize remains
    try testing.expect(!manager.has(ClearColor));
    try testing.expect(manager.has(WindowSize));

    // Try to remove ClearColor again (should return false)
    const removed_again = manager.remove(ClearColor);
    try testing.expect(!removed_again);

    // WindowSize should still be accessible
    const size = manager.get(WindowSize).?;
    try testing.expectEqual(@as(u32, 800), size.width);
}

test "ResourceManager get non-existent resource returns null" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Try to get a resource that doesn't exist
    const color = manager.get(ClearColor);
    try testing.expect(color == null);
}

test "ResourceManager with zero-sized types" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert zero-sized type
    try manager.insert(GameMarker{});
    
    // Should be able to check if it exists
    try testing.expect(manager.has(GameMarker));
    
    // Should be able to get it back
    const marker = manager.get(GameMarker).?;
    _ = marker; // Suppress unused variable warning
    
    // Should be able to remove it
    const removed = manager.remove(GameMarker);
    try testing.expect(removed);
    try testing.expect(!manager.has(GameMarker));
}

test "ResourceManager with large resources" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert large resource
    var large_resource = LargeResource.init();
    large_resource.data[0] = 42;
    large_resource.data[1023] = 99;
    
    try manager.insert(large_resource);
    
    // Verify it was stored correctly
    try testing.expect(manager.has(LargeResource));
    const retrieved = manager.get(LargeResource).?;
    try testing.expectEqual(@as(u8, 42), retrieved.data[0]);
    try testing.expectEqual(@as(u8, 99), retrieved.data[1023]);
}

test "ResourceManager with string resources" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert resource with string data
    const config = GameConfig{
        .max_players = 4,
        .level_count = 10,
        .title = "Test Game",
    };
    try manager.insert(config);
    
    // Verify string data is preserved
    const retrieved_config = manager.get(GameConfig).?;
    try testing.expectEqual(@as(u32, 4), retrieved_config.max_players);
    try testing.expectEqual(@as(u32, 10), retrieved_config.level_count);
    try testing.expectEqualStrings("Test Game", retrieved_config.title);
}

test "ResourceManager stress test with many resources" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Add multiple resources of the same type (they should replace each other)
    for (0..100) |i| {
        const color = ClearColor{
            .r = @as(f32, @floatFromInt(i)) / 100.0,
            .g = 0.5,
            .b = 0.0,
            .a = 1.0,
        };
        try manager.insert(color);
    }

    // Should only have one ClearColor (the last one)
    try testing.expect(manager.has(ClearColor));
    const final_color = manager.get(ClearColor).?;
    try testing.expectEqual(@as(f32, 99.0 / 100.0), final_color.r);
}

test "resourceId function consistency" {
    // Test that resourceId generates consistent IDs
    const id1 = resourceId(ClearColor);
    const id2 = resourceId(ClearColor);
    try testing.expectEqual(id1, id2);

    // Test with instance vs type
    const color_instance = ClearColor{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    const id3 = resourceId(color_instance);
    try testing.expectEqual(id1, id3);

    // Different types should have different IDs
    const window_id = resourceId(WindowSize);
    try testing.expect(id1 != window_id);
}

test "ResourceManager integration with Database" {
    var db = Database.init(testing.allocator);
    defer db.deinit();

    // Test Database resource methods
    const config = GameConfig{
        .max_players = 8,
        .level_count = 20,
        .title = "Integration Test",
    };
    
    try db.insertResource(config);
    try testing.expect(db.hasResource(GameConfig));
    
    const retrieved = db.getResource(GameConfig).?;
    try testing.expectEqual(@as(u32, 8), retrieved.max_players);
    try testing.expectEqualStrings("Integration Test", retrieved.title);
    
    const removed = db.removeResource(GameConfig);
    try testing.expect(removed);
    try testing.expect(!db.hasResource(GameConfig));
}

test "ResourceManager memory cleanup on replace" {
    var manager = ResourceManager.init(testing.allocator);
    defer manager.deinit();

    // Insert a large resource
    var large1 = LargeResource.init();
    large1.data[0] = 1;
    try manager.insert(large1);

    // Replace it with another large resource
    var large2 = LargeResource.init();
    large2.data[0] = 2;
    try manager.insert(large2);

    // Verify the new resource is there and has correct data
    const retrieved = manager.get(LargeResource).?;
    try testing.expectEqual(@as(u8, 2), retrieved.data[0]);
    
    // Memory should have been properly cleaned up (verified by allocator)
}