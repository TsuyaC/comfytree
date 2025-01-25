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
    glfw.WindowHint(glfw.RESIZABLE, 0)

    window = glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)
    if window == nil {
        LogError("GLFW failed to load window!")
    }
}

CleanupGlfw :: proc(using ctx: ^VulkanContext)
{
    glfw.DestroyWindow(window)
    glfw.Terminate()
}