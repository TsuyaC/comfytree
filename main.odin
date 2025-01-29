package engine

import "core:fmt"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"


// ███████ ███    ██  ██████  ██ ███    ██ ███████ 
// ██      ████   ██ ██       ██ ████   ██ ██      
// █████   ██ ██  ██ ██   ███ ██ ██ ██  ██ █████   
// ██      ██  ██ ██ ██    ██ ██ ██  ██ ██ ██      
// ███████ ██   ████  ██████  ██ ██   ████ ███████ 


WIDTH :: 1920
HEIGHT :: 1080
TITLE :: "Comfytree"
DETAILED_INFO :: false  // Currently used only for Vulkan (OpenGL not implemented)

InitBackend :: proc(using ctx: ^VulkanContext, api: API, vertices: []Vertex, indices: []u16) 
{
    if api == .OpenGL {
        LogError("OPENGL NOT IMPLEMENTED!")
        os.exit(1)
    }

    if api == .Vulkan {
        fmt.println("\x1b[92mUsing Vulkan Backend\x1b[0m\n")
        InitWindow(ctx)
        InitVulkan(ctx, vertices, indices)
    }
}

CleanupBackend :: proc(using ctx: ^VulkanContext, api: API)
{
    if api == .OpenGL {
        return
    }

    if api == .Vulkan {
        CleanupVulkan(ctx)
    }
}

main :: proc()
{
    fmt.println("\x1b[92mComfytree\x1b[0m\n")
    // Vulkan
    api: API = .Vulkan
    using ctx : VulkanContext

    vertices := [?]Vertex {
		{{-0.5, -0.5,  0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
		{{ 0.5, -0.5,  0.0}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
		{{ 0.5,  0.5,  0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
        {{-0.5,  0.5,  0.0}, {1.0, 1.0, 1.0}, {0.0, 1.0}},

		{{-0.5, -0.5, -0.5}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
		{{ 0.5, -0.5, -0.5}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
		{{ 0.5,  0.5, -0.5}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
        {{-0.5,  0.5, -0.5}, {1.0, 1.0, 1.0}, {0.0, 1.0}},
    }

    indices := [?]u16 {
        0, 1, 2, 2, 3, 0,
        4, 5, 6, 6, 7, 4,
    }

    InitBackend(&ctx, api, vertices[:], indices[:])

    for !glfw.WindowShouldClose(window)
    {
        glfw.PollEvents()
        if glfw.PRESS == glfw.GetKey(window, glfw.KEY_F5) {
            ReloadShaderModules(&ctx)
        }
        DrawFrame(&ctx, vertices[:], indices[:])
    }

    CleanupBackend(&ctx, api)
    CleanupGlfw(&ctx)
}