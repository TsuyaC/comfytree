package engine

import "core:fmt"
import "vendor:glfw"


// ██████  ██      ███████ ██     ██ 
// ██       ██      ██      ██     ██ 
// ██   ███ ██      █████   ██  █  ██ 
// ██    ██ ██      ██      ██ ███ ██ 
//  ██████  ███████ ██       ███ ███  


InitWindow :: proc(using ctx: ^VulkanContext)
{
    if(!glfw.Init()) {
        LogError("Failed to init GLFW!")
        return
    }
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    // glfw.WindowHint(glfw.RESIZABLE, 0)

    window = glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)
    if window == nil {
        LogError("GLFW failed to load window!")
    }

    glfw.SetWindowUserPointer(window, ctx)
    glfw.SetFramebufferSizeCallback(window, FrameBufferResizeCallback)
}

CleanupGlfw :: proc(using ctx: ^VulkanContext)
{
    glfw.DestroyWindow(window)
    glfw.Terminate()
}

FrameBufferResizeCallback :: proc "c" (window: glfw.WindowHandle, width, height: i32)
{
    using ctx := cast(^VulkanContext)glfw.GetWindowUserPointer(window)
    framebufferResized = true
}