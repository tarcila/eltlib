//
// cc sdl-metal-example.m `sdl2-config --cflags --libs` -framework Metal -framework QuartzCore && ./a.out
//
#include <SDL3/SDL.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <assert.h>
#include <stdlib.h>

#include "mainwindow.h"

struct Window {
    SDL_Window *window;
    SDL_Renderer *renderer;
    CAMetalLayer *swapchain;
    id<MTLDevice> gpu;
    id<MTLCommandQueue> queue;
    float time;
};

#define MAX_WINDOWS 10
unsigned int g_windows_count = 0;
struct Window g_windows[MAX_WINDOWS] = {0};
bool g_windows_used[MAX_WINDOWS] = {false};

struct Window* createWindow(unsigned int width, unsigned int height)
{
    unsigned int window_idx = 0;
    for (; window_idx < MAX_WINDOWS; ++window_idx) {
        if (!g_windows_used[window_idx]) { break; }
    }

    if (window_idx == MAX_WINDOWS) {
        return NULL;
    }

    g_windows_used[window_idx] = true;
    ++g_windows_count;

    // First window created
    if (g_windows_count == 1)
    {
        SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
        SDL_InitSubSystem(SDL_INIT_VIDEO);
    }
    struct Window* window = &g_windows[window_idx];

    window->window = SDL_CreateWindow("SDL Metal", 640, 480, SDL_WINDOW_HIGH_PIXEL_DENSITY);
    window->renderer = SDL_CreateRenderer(window->window, NULL, SDL_RENDERER_PRESENTVSYNC);
    window->swapchain = (__bridge CAMetalLayer *)SDL_GetRenderMetalLayer(window->renderer);
    window->gpu = window->swapchain.device;
    window->queue = [window->gpu newCommandQueue];
    window->time = 0.0f;

    return &g_windows[window_idx];
}

void destroyWindow(struct Window* window) {
    SDL_DestroyRenderer(window->renderer);
    SDL_DestroyWindow(window->window);

    unsigned int window_idx = window - g_windows;
    assert(window_idx < MAX_WINDOWS);

    g_windows_count--;
    g_windows_used[window_idx] = false;
    if (g_windows_count == 0) {
        SDL_Quit();
    }
}

enum Event pollEvent() {
    SDL_Event e;
    if (SDL_PollEvent(&e)) {
        switch (e.type) {
            case SDL_EVENT_QUIT: return QUIT;
        }
    }

    return NO_EVENT;
}

void sendFrame(struct Window* window) {
        MTLClearColor color = MTLClearColorMake(0, 0, 0, 1);
        float time = window->time;
        window->time += 0.01f;

        @autoreleasepool {
            id<CAMetalDrawable> surface = [window->swapchain nextDrawable];

            color.red = time - floor(time);

            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].clearColor = color;
            pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.colorAttachments[0].texture = surface.texture;

            id<MTLCommandBuffer> buffer = [window->queue commandBuffer];
            id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
            [encoder endEncoding];
            [buffer presentDrawable:surface];
            [buffer commit];
        }
}
