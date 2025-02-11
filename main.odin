package engine

import "core:fmt"
import "vendor:glfw"


// ███████ ███    ██  ██████  ██ ███    ██ ███████ 
// ██      ████   ██ ██       ██ ████   ██ ██      
// █████   ██ ██  ██ ██   ███ ██ ██ ██  ██ █████   
// ██      ██  ██ ██ ██    ██ ██ ██  ██ ██ ██      
// ███████ ██   ████  ██████  ██ ██   ████ ███████ 


WIDTH :: 1920
HEIGHT :: 1080
TITLE :: "Comfytree"
DETAILED_INFO :: false      // Currently used only for Vulkan (OpenGL not implemented)
LOG_MINIMAL :: false        // Only log errors

MSAA_ENABLED :: false
MIPMAPS_ENABLED :: true
FLIP_UV :: true             // flips vertical part of UV coords (use for vulkan)

DYNAMIC_RENDERING :: true

objName :: "./assets/mesh/viking_room.obj"
objTex  :: "./assets/textures/viking_room.png"

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
            ReloadShaders(&ctx)
        }

        DrawFrame(&ctx, verticesObj[:], indicesObj[:])
    }

    CleanupBackend(&ctx, api)
    CleanupGlfw(&ctx)
}