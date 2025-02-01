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
LOG_MINIMAL :: false     // Only log errors
MSAA_ENABLED :: false
MIPMAPS_ENABLED :: false
FLIP_UV :: true         // flips vertical part of UV coords (use for vulkan)

objName :: "./mesh/viking_room.obj"
objTex  :: "./textures/viking_room.png"

InitBackend :: proc(using ctx: ^VulkanContext, api: API, vertices: []Vertex, indices: []u32) 
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
    fmt.println("\x1b[92mComfytree\x1b[0m")
    // Vulkan
    api: API = .Vulkan
    using ctx : VulkanContext

    verticesObj, testNormals, indicesObj := LoadObj(objName)
    InitBackend(&ctx, api, verticesObj[:], indicesObj[:])

    for !glfw.WindowShouldClose(window)
    {
        glfw.PollEvents()
        if glfw.PRESS == glfw.GetKey(window, glfw.KEY_F5) {
            ReloadShaderModules(&ctx)
        }
        DrawFrame(&ctx, verticesObj[:], indicesObj[:])
    }

    CleanupBackend(&ctx, api)
    CleanupGlfw(&ctx)
}