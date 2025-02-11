package engine

import "core:fmt"
import "core:mem"
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

MSAA_ENABLED :: true
MIPMAPS_ENABLED :: true
FLIP_UV :: true             // flips vertical part of UV coords (use for vulkan)

DYNAMIC_RENDERING :: true

objName :: "./assets/mesh/viking_room.obj"
objTex  :: "./assets/textures/viking_room.png"

main :: proc()
{
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("-%p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    fmt.println("\x1b[92mComfytree\x1b[0m")
    // Vulkan
    api: API = .Vulkan
    using ctx : VulkanContext

    verticesObj, testNormals, indicesObj := LoadObj(objName)
    defer{
        delete(verticesObj)
        delete(testNormals)
        delete(indicesObj)
    }
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
    Cleanup(&ctx)
}

Cleanup :: proc(using ctx: ^VulkanContext)
{
    delete(uniformBuffers)
    delete(descriptorSets)
    delete(swapchain.framebuffers)
    delete(swapchain.imageViews)
    delete(swapchain.images)
    delete(swapchain.support.formats)
    delete(swapchain.support.presentModes)
}