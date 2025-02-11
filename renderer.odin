package engine

import "core:fmt"
import "core:os"


API :: enum {
    Vulkan,
    OpenGL,
}

InitBackend :: proc(using ctx: ^VulkanContext, api: API, vertices: []Vertex, indices: []u32) 
{
    if api == .OpenGL {
        LogError("OPENGL NOT IMPLEMENTED!")
        os.exit(1)
    }

    if api == .Vulkan {
        fmt.println("\x1b[92mUsing Vulkan Backend\x1b[0m\n")
        InitWindow(ctx)

        if DYNAMIC_RENDERING {
            InitVulkanDR(ctx, vertices, indices)
        } else {
            InitVulkan(ctx, vertices, indices)
        }
    }
}

CleanupBackend :: proc(using ctx: ^VulkanContext, api: API)
{
    if api == .OpenGL {
        return
    }

    if api == .Vulkan {
        if DYNAMIC_RENDERING {
            CleanupVulkanDR(ctx)
        } else {
            CleanupVulkan(ctx)
        }
    }
}

DrawFrame :: proc(using ctx: ^VulkanContext, vertices: []Vertex, indices: []u32)
{
    if DYNAMIC_RENDERING {
        DrawFrameDR(ctx, vertices, indices)
    } else {
        DrawFrameFB(ctx, vertices, indices)
    }
}

ReloadShaders :: proc(using ctx: ^VulkanContext)
{
    if DYNAMIC_RENDERING {
        ReloadShaderModulesDR(ctx)
    } else {
        ReloadShaderModules(ctx)
    }
}