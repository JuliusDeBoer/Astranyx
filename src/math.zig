pub const Vec2 = struct {
    const Self = @This();

    x: f32,
    y: f32,

    pub fn empty() Self {
        return Self{ .x = 0, .y = 0 };
    }
};

pub const Vec3 = struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,

    pub fn empty() Self {
        return Self{ .x = 0, .y = 0, .z = 0 };
    }
};
