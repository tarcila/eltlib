#pragma once

enum Event {
    NO_EVENT = -1,
    QUIT = 0,
};

struct Window;
struct CommandQueue;

struct Window* createWindow(unsigned int width, unsigned int height);
struct CommandQueue* getCommandQueue(struct Window*);
void sendFrame(struct Window* window);
void destroyWindow(struct Window* window);

enum Event pollEvent();
