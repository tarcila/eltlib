const std = @import("std");

pub fn build(b: *std.Build) void {
    //
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Depends on SDL source files
    const libsdlsrc = b.dependency("sdl3src", .{ .target = target, .optimize = optimize });

    // Build a static library out of that
    const sdl = b.addStaticLibrary(.{ .name = "libsdl3", .target = target, .optimize = optimize });

    // const sdl = b.addModule("sdl3", .{});
    sdl.addIncludePath(libsdlsrc.path("include"));
    sdl.addIncludePath(libsdlsrc.path("src"));
    for (generic_src_files) |file| sdl.addCSourceFile(.{ .file = libsdlsrc.path(file), .flags = &.{} });

    sdl.defineCMacro("SDL_USE_BUILTIN_OPENGL_DEFINITIONS", "1");
    sdl.linkLibC();

    switch (target.result.os.tag) {
        .windows => {
            for (windows_src_files) |file| {
                sdl.addCSourceFile(.{ .file = libsdlsrc.path(file), .flags = &.{} });
            }
            sdl.linkSystemLibrary("setupapi");
            sdl.linkSystemLibrary("winmm");
            sdl.linkSystemLibrary("gdi32");
            sdl.linkSystemLibrary("imm32");
            sdl.linkSystemLibrary("version");
            sdl.linkSystemLibrary("oleaut32");
            sdl.linkSystemLibrary("ole32");
        },
        .macos => {
            for (macos_src_files) |file| {
                if (std.mem.endsWith(u8, file, ".m")) {
                    sdl.addCSourceFile(.{ .file = libsdlsrc.path(file), .flags = &.{"-fobjc-arc"} });
                } else {
                    sdl.addCSourceFile(.{ .file = libsdlsrc.path(file), .flags = &.{} });
                }
            }
            sdl.linkFramework("AVFoundation");
            sdl.linkFramework("AudioToolbox");
            sdl.linkFramework("Carbon");
            sdl.linkFramework("Cocoa");
            sdl.linkFramework("CoreAudio");
            sdl.linkFramework("CoreHaptics");
            sdl.linkFramework("CoreVideo");
            sdl.linkFramework("CoreVideo");
            sdl.linkFramework("ForceFeedback");
            sdl.linkFramework("Foundation");
            sdl.linkFramework("GameController");
            sdl.linkFramework("IOKit");
            sdl.linkFramework("OpenGL");
            sdl.linkFrameworkWeak("Metal");
            sdl.linkFrameworkWeak("QuartzCore");
            sdl.linkSystemLibrary("objc");
        },
        else => {
            const config_header = b.addConfigHeader(.{
                .style = .{ .cmake = libsdlsrc.path("include/SDL_config.h.cmake") },
                .include_path = "SDL3/SDL_config.h",
            }, .{});
            sdl.addConfigHeader(config_header);
            // sdl.installConfigHeader(config_header, .{});
        },
    }
    sdl.installHeadersDirectoryOptions(.{
        .source_dir = libsdlsrc.path("include/SDL3/"),
        .install_dir = .header,
        .install_subdir = "SDL3",
    });
    b.installArtifact(sdl);
}

const generic_src_files = [_][]const u8{};

const windows_src_files = [_][]const u8{};

const linux_src_files = [_][]const u8{};

const macos_src_files = [_][]const u8{
    "src/SDL.c",
    "src/SDL_assert.c",
    "src/SDL_error.c",
    "src/SDL_guid.c",
    "src/SDL_hashtable.c",
    "src/SDL_hints.c",
    "src/SDL_list.c",
    "src/SDL_log.c",
    "src/SDL_properties.c",
    "src/SDL_utils.c",
    "src/atomic/SDL_atomic.c",
    "src/atomic/SDL_spinlock.c",
    "src/audio/SDL_audio.c",
    "src/audio/SDL_audiocvt.c",
    "src/audio/SDL_audiodev.c",
    "src/audio/SDL_audioqueue.c",
    "src/audio/SDL_audioresample.c",
    "src/audio/SDL_audiotypecvt.c",
    "src/audio/SDL_mixer.c",
    "src/audio/SDL_wave.c",
    "src/audio/coreaudio/SDL_coreaudio.m",
    "src/audio/disk/SDL_diskaudio.c",
    "src/audio/dummy/SDL_dummyaudio.c",
    "src/core/SDL_core_unsupported.c",
    "src/core/SDL_runapp.c",
    "src/cpuinfo/SDL_cpuinfo.c",
    "src/dynapi/SDL_dynapi.c",
    "src/events/SDL_clipboardevents.c",
    "src/events/SDL_displayevents.c",
    "src/events/SDL_dropevents.c",
    "src/events/SDL_events.c",
    "src/events/SDL_keyboard.c",
    "src/events/SDL_keysym_to_scancode.c",
    "src/events/SDL_mouse.c",
    "src/events/SDL_pen.c",
    "src/events/SDL_quit.c",
    "src/events/SDL_scancode_tables.c",
    "src/events/SDL_touch.c",
    "src/events/SDL_windowevents.c",
    "src/events/imKStoUCS.c",
    "src/file/SDL_rwops.c",
    "src/file/cocoa/SDL_rwopsbundlesupport.m",
    "src/filesystem/cocoa/SDL_sysfilesystem.m",
    "src/haptic/SDL_haptic.c",
    "src/haptic/darwin/SDL_syshaptic.c",
    "src/hidapi/SDL_hidapi.c",
    "src/joystick/SDL_gamepad.c",
    "src/joystick/SDL_joystick.c",
    "src/joystick/SDL_steam_virtual_gamepad.c",
    "src/joystick/apple/SDL_mfijoystick.m",
    "src/joystick/controller_type.c",
    "src/joystick/darwin/SDL_iokitjoystick.c",
    "src/joystick/hidapi/SDL_hidapi_combined.c",
    "src/joystick/hidapi/SDL_hidapi_gamecube.c",
    "src/joystick/hidapi/SDL_hidapi_luna.c",
    "src/joystick/hidapi/SDL_hidapi_ps3.c",
    "src/joystick/hidapi/SDL_hidapi_ps4.c",
    "src/joystick/hidapi/SDL_hidapi_ps5.c",
    "src/joystick/hidapi/SDL_hidapi_rumble.c",
    "src/joystick/hidapi/SDL_hidapi_shield.c",
    "src/joystick/hidapi/SDL_hidapi_stadia.c",
    "src/joystick/hidapi/SDL_hidapi_steam.c",
    "src/joystick/hidapi/SDL_hidapi_steamdeck.c",
    "src/joystick/hidapi/SDL_hidapi_switch.c",
    "src/joystick/hidapi/SDL_hidapi_wii.c",
    "src/joystick/hidapi/SDL_hidapi_xbox360.c",
    "src/joystick/hidapi/SDL_hidapi_xbox360w.c",
    "src/joystick/hidapi/SDL_hidapi_xboxone.c",
    "src/joystick/hidapi/SDL_hidapijoystick.c",
    "src/joystick/virtual/SDL_virtualjoystick.c",
    "src/libm/e_atan2.c",
    "src/libm/e_exp.c",
    "src/libm/e_fmod.c",
    "src/libm/e_log.c",
    "src/libm/e_log10.c",
    "src/libm/e_pow.c",
    "src/libm/e_rem_pio2.c",
    "src/libm/e_sqrt.c",
    "src/libm/k_cos.c",
    "src/libm/k_rem_pio2.c",
    "src/libm/k_sin.c",
    "src/libm/k_tan.c",
    "src/libm/s_atan.c",
    "src/libm/s_copysign.c",
    "src/libm/s_cos.c",
    "src/libm/s_fabs.c",
    "src/libm/s_floor.c",
    "src/libm/s_modf.c",
    "src/libm/s_scalbn.c",
    "src/libm/s_sin.c",
    "src/libm/s_tan.c",
    "src/loadso/dlopen/SDL_sysloadso.c",
    "src/locale/SDL_locale.c",
    "src/locale/macos/SDL_syslocale.m",
    "src/main/SDL_main_callbacks.c",
    "src/main/generic/SDL_sysmain_callbacks.c",
    "src/misc/SDL_url.c",
    "src/misc/macos/SDL_sysurl.m",
    "src/power/SDL_power.c",
    "src/power/macos/SDL_syspower.c",
    "src/render/SDL_d3dmath.c",
    "src/render/SDL_render.c",
    "src/render/SDL_render_unsupported.c",
    "src/render/SDL_yuv_sw.c",
    "src/render/direct3d/SDL_render_d3d.c",
    "src/render/direct3d/SDL_shaders_d3d.c",
    "src/render/direct3d11/SDL_render_d3d11.c",
    "src/render/direct3d11/SDL_shaders_d3d11.c",
    "src/render/direct3d12/SDL_render_d3d12.c",
    "src/render/direct3d12/SDL_shaders_d3d12.c",
    "src/render/metal/SDL_render_metal.m",
    "src/render/opengl/SDL_render_gl.c",
    "src/render/opengl/SDL_shaders_gl.c",
    "src/render/opengles2/SDL_render_gles2.c",
    "src/render/opengles2/SDL_shaders_gles2.c",
    "src/render/ps2/SDL_render_ps2.c",
    "src/render/psp/SDL_render_psp.c",
    "src/render/software/SDL_blendfillrect.c",
    "src/render/software/SDL_blendline.c",
    "src/render/software/SDL_blendpoint.c",
    "src/render/software/SDL_drawline.c",
    "src/render/software/SDL_drawpoint.c",
    "src/render/software/SDL_render_sw.c",
    "src/render/software/SDL_rotate.c",
    "src/render/software/SDL_triangle.c",
    "src/render/vitagxm/SDL_render_vita_gxm.c",
    "src/render/vitagxm/SDL_render_vita_gxm_memory.c",
    "src/render/vitagxm/SDL_render_vita_gxm_tools.c",
    "src/sensor/SDL_sensor.c",
    "src/sensor/dummy/SDL_dummysensor.c",
    "src/stdlib/SDL_crc16.c",
    "src/stdlib/SDL_crc32.c",
    "src/stdlib/SDL_getenv.c",
    "src/stdlib/SDL_iconv.c",
    "src/stdlib/SDL_malloc.c",
    "src/stdlib/SDL_memcpy.c",
    "src/stdlib/SDL_memmove.c",
    "src/stdlib/SDL_memset.c",
    "src/stdlib/SDL_mslibc.c",
    "src/stdlib/SDL_qsort.c",
    "src/stdlib/SDL_stdlib.c",
    "src/stdlib/SDL_string.c",
    "src/stdlib/SDL_strtokr.c",
    "src/test/SDL_test_assert.c",
    "src/test/SDL_test_common.c",
    "src/test/SDL_test_compare.c",
    "src/test/SDL_test_crc32.c",
    "src/test/SDL_test_font.c",
    "src/test/SDL_test_fuzzer.c",
    "src/test/SDL_test_harness.c",
    "src/test/SDL_test_log.c",
    "src/test/SDL_test_md5.c",
    "src/test/SDL_test_memory.c",
    "src/test/SDL_test_random.c",
    "src/thread/SDL_thread.c",
    "src/thread/pthread/SDL_syscond.c",
    "src/thread/pthread/SDL_sysmutex.c",
    "src/thread/pthread/SDL_sysrwlock.c",
    "src/thread/pthread/SDL_syssem.c",
    "src/thread/pthread/SDL_systhread.c",
    "src/thread/pthread/SDL_systls.c",
    "src/timer/SDL_timer.c",
    "src/timer/unix/SDL_systimer.c",
    "src/video/SDL_RLEaccel.c",
    "src/video/SDL_blit.c",
    "src/video/SDL_blit_0.c",
    "src/video/SDL_blit_1.c",
    "src/video/SDL_blit_A.c",
    "src/video/SDL_blit_N.c",
    "src/video/SDL_blit_auto.c",
    "src/video/SDL_blit_copy.c",
    "src/video/SDL_blit_slow.c",
    "src/video/SDL_bmp.c",
    "src/video/SDL_clipboard.c",
    "src/video/SDL_egl.c",
    "src/video/SDL_fillrect.c",
    "src/video/SDL_pixels.c",
    "src/video/SDL_rect.c",
    "src/video/SDL_stretch.c",
    "src/video/SDL_surface.c",
    "src/video/SDL_video.c",
    "src/video/SDL_video_capture.c",
    "src/video/SDL_video_capture_apple.m",
    "src/video/SDL_video_capture_v4l2.c",
    "src/video/SDL_video_unsupported.c",
    "src/video/SDL_vulkan_utils.c",
    "src/video/SDL_yuv.c",
    "src/video/cocoa/SDL_cocoaclipboard.m",
    "src/video/cocoa/SDL_cocoaevents.m",
    "src/video/cocoa/SDL_cocoakeyboard.m",
    "src/video/cocoa/SDL_cocoamessagebox.m",
    "src/video/cocoa/SDL_cocoametalview.m",
    "src/video/cocoa/SDL_cocoamodes.m",
    "src/video/cocoa/SDL_cocoamouse.m",
    "src/video/cocoa/SDL_cocoaopengl.m",
    "src/video/cocoa/SDL_cocoaopengles.m",
    "src/video/cocoa/SDL_cocoavideo.m",
    "src/video/cocoa/SDL_cocoavulkan.m",
    "src/video/cocoa/SDL_cocoawindow.m",
    "src/video/dummy/SDL_nullevents.c",
    "src/video/dummy/SDL_nullframebuffer.c",
    "src/video/dummy/SDL_nullvideo.c",
    "src/video/offscreen/SDL_offscreenevents.c",
    "src/video/offscreen/SDL_offscreenframebuffer.c",
    "src/video/offscreen/SDL_offscreenopengles.c",
    "src/video/offscreen/SDL_offscreenvideo.c",
    "src/video/offscreen/SDL_offscreenwindow.c",
    "src/video/yuv2rgb/yuv_rgb_lsx.c",
    "src/video/yuv2rgb/yuv_rgb_sse.c",
    "src/video/yuv2rgb/yuv_rgb_std.c",
};
