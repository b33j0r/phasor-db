pub fn Resource(comptime T: type) type {
    return struct {
        value: T,
    };
}
