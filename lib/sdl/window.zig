const std = @import("std");
const CommandQueue = @import("../sdl.zig").CommandQueue;

pub const WindowError = error{
    CannotCreateWindow,
};

const MainWindow = @This();

pub fn createWindow(width: u32, height: u32) !*MainWindow {
    if (c.createWindow(width, height)) |window| {
        return window;
    } else {
        return WindowError.CannotCreateWindow;
    }
}

pub fn getCommandQueue(self: *MainWindow) !*CommandQueue {
    return c.getCommandQueue(self);
}

pub fn sendFrame(self: *MainWindow) void {
    c.sendFrame(self);
}

pub fn destroyWindow(self: *MainWindow) void {
    c.destroyWindow(self);
}

const c = struct {
    extern fn createWindow(width: c_uint, height: c_uint) ?*MainWindow;
    extern fn getCommandQueue(*MainWindow) *CommandQueue;
    extern fn sendFrame(window: *MainWindow) void;
    extern fn destroyWindow(window: *MainWindow) void;
};
