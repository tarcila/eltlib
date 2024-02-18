const KeyCode = @import("key.zig").Keycode;
const MouseButton = @import("pointer.zig").MouseButton;
const Point2d = @import("../core/point.zig").Point2d;
const Vector2d = @import("../core/vector.zig").Vector2d;

ptr: *anyopaque,
vtable: VTable,

pub const VTable = struct {};

const PointerBehavior = struct {
    pub fn handleViewportChanged(viewport_origin: Point2d, viewport_size: Vector2d) void;

    pub fn handleKeyPressed(keycode: KeyCode) void;
    pub fn handleKeyReleased(keycode: KeyCode) void;
    pub fn handleMouseMoved(pointer_position: Point2d) void;

    pub fn handleMouseButtonClicked(button_id: MouseButton, pointer_position: Point2d) void;
    pub fn handleMouseButtonDoubleClicked(button_id: MouseButton, pointer_position: Point2d) void;
    pub fn handleMouseButtonPressed(button_id: MouseButton, pointer_position: Point2d) void;
    pub fn handleMouseButtonReleased(button_id: MouseButton, pointer_position: Point2d) void;
    pub fn handleMouseWheelScrolled(delta_x: isize, delta_y: isize) void;
    pub fn update() void;
};
