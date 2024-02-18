const std = @import("std");
const mach_objc = @import("mach-objc");
const ca = mach_objc.quartz_core.ca;
const mtl = mach_objc.metal.mtl;
const objc = mach_objc.objc;

const c = @cImport(@cInclude("SDL3/SDL.h"));

pub const Event = enum {
    QUIT,
};

pub const SetupError = error{
    CannotSetRenderDriverHint,
    CannotInitSubsystem,
};

pub fn setUp() !void {
    // FIXME: Handle errors
    if (c.SDL_SetHint(c.SDL_HINT_RENDER_DRIVER, "metal") != c.SDL_TRUE) {
        std.debug.print("Cannot set 'metal' driver hint for SDL.", .{});
        return SetupError.CannotSetRenderDriverHint;
    }
    if (c.SDL_InitSubSystem(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("Failed initializing video subsystem for SDL", .{});
        return SetupError.CannotInitSubsystem;
    }
}

pub fn tearDown() void {
    c.SDL_Quit();
}

pub fn pollEvent() ?Event {
    var e: c.SDL_Event = undefined;

    if (c.SDL_PollEvent(&e) == c.SDL_TRUE) {
        return switch (e.type) {
            c.SDL_EVENT_QUIT => .QUIT,
            else => null,
        };
    }
    return null;
}

fn logsdlerror() void {
    std.debug.print("<SDLERROR:\"{s}\">", .{c.SDL_GetError()});
}

pub const MainWindowError = error{
    CannotCreateWindow,
    CannotCreateRender,
    CannotGetRenderMetalLayer,
    CannotGetMetalDevice,
    CannotCreateCommandQueue,
};

pub const MainWindow = struct {
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    metal_layer: *ca.MetalLayer,
    device: *mtl.Device,
    queue: *mtl.CommandQueue,
    time: f32,

    pub fn createWindow(title: []const u8, width: usize, height: usize) !MainWindow {
        const window = window_blk: {
            if (c.SDL_CreateWindow(@ptrCast(title), @intCast(width), @intCast(height), c.SDL_WINDOW_HIGH_PIXEL_DENSITY)) |w| {
                break :window_blk w;
            } else {
                logsdlerror();
                return MainWindowError.CannotCreateWindow;
            }
        };

        const renderer = renderer_blk: {
            if (c.SDL_CreateRenderer(window, null, c.SDL_RENDERER_PRESENTVSYNC)) |r| {
                break :renderer_blk r;
            } else {
                logsdlerror();
                return MainWindowError.CannotCreateRender;
            }
        };
        const metal_layer = metal_layer_blk: {
            if (c.SDL_GetRenderMetalLayer(renderer)) |ml| {
                break :metal_layer_blk @as(*ca.MetalLayer, @ptrCast(@alignCast(ml)));
            } else {
                logsdlerror();
                return MainWindowError.CannotGetRenderMetalLayer;
            }
        };
        const device = device_blk: {
            if (metal_layer.device()) |d| {
                break :device_blk d;
            } else {
                logsdlerror();
                return MainWindowError.CannotGetMetalDevice;
            }
        };

        const queue = queue_blk: {
            if (device.newCommandQueue()) |q| {
                break :queue_blk q;
            } else {
                logsdlerror();
                return MainWindowError.CannotCreateCommandQueue;
            }
        };
        return MainWindow{
            .window = window,
            .renderer = renderer,
            .metal_layer = metal_layer,
            .device = device,
            .queue = queue,
            .time = 0,
        };
    }

    pub fn getDevice(self: MainWindow) mtl.Device {
        return self.device;
    }

    pub fn submitCommandBuffer(buffer: mtl.CommandBuffer) void {
        _ = buffer; // autofix
    }

    pub fn sendFrame(self: *MainWindow) void {
        const time = self.time;
        self.time += 0.01;

        const pool = objc.autoreleasePoolPush();
        defer objc.autoreleasePoolPop(pool);

        const surface = self.metal_layer.nextDrawable().?;
        const red = time - @floor(time);
        const clearColor = mtl.ClearColor.init(red, 0, 0, 1);

        const renderPassDescriptor = mtl.RenderPassDescriptor.renderPassDescriptor();
        const colorAttachments = renderPassDescriptor.colorAttachments();
        const colorAttachment0 = colorAttachments.objectAtIndexedSubscript(0);
        colorAttachment0.setClearColor(clearColor);
        colorAttachment0.setLoadAction(mtl.LoadActionClear);
        colorAttachment0.setStoreAction(mtl.StoreActionStore);
        colorAttachment0.setTexture(surface.texture());

        const buffer = self.queue.commandBuffer().?;
        const encoder = buffer.renderCommandEncoderWithDescriptor(renderPassDescriptor).?;

        encoder.endEncoding();
        buffer.presentDrawable(@ptrCast(surface));
        buffer.commit();
    }

    pub fn destroy(self: MainWindow) void {
        // self.queue.release();
        // self.device.release();

        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
