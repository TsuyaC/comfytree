package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"
import "shared:shaderc"


// ██    ██ ██    ██ ██      ██   ██  █████  ███    ██ 
// ██    ██ ██    ██ ██      ██  ██  ██   ██ ████   ██ 
// ██    ██ ██    ██ ██      █████   ███████ ██ ██  ██ 
//  ██  ██  ██    ██ ██      ██  ██  ██   ██ ██  ██ ██ 
//   ████    ██████  ███████ ██   ██ ██   ██ ██   ████ 

@(private="file")
MAX_FRAMES_IN_FLIGHT :: 2
@(private="file")
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};
@(private="file")
DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"};

when ODIN_DEBUG {
    enableValidationLayers :: true
} else {
    enableValidationLayers :: false
}


VERTEX_BINDING := vk.VertexInputBindingDescription {
    binding = 0,
    stride = size_of(Vertex),
    inputRate = .VERTEX
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription {
    {
        binding = 0,
        location = 0,
        format = .R32G32_SFLOAT,
        offset = cast(u32)offset_of(Vertex, pos),
    },
    {
        binding = 0,
        location = 1,
        format = .R32G32B32_SFLOAT,
        offset = cast(u32)offset_of(Vertex, color),
    },
}

VulkanContext :: struct {
    window:                 glfw.WindowHandle,
    instance:               vk.Instance,
    device:                 vk.Device,
    physicalDevice:         vk.PhysicalDevice,
    physicalDeviceProps:    vk.PhysicalDeviceProperties,
    surface:                vk.SurfaceKHR,
    queueIndices:           [QueueFamily]int,
    queues:                 [QueueFamily]vk.Queue,
    swapchain:              Swapchain,
    oldSwapchain:           Swapchain,
    pipeline:               Pipeline,
    commandPool:            vk.CommandPool,
    commandBuffers:         [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    vertexBuffer:           Buffer,
    indexBuffer:            Buffer,

    imageAvailable:         [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinished:         [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlight:               [MAX_FRAMES_IN_FLIGHT]vk.Fence,

    curFrame:               u32,
    framebufferResized:     bool,
}

@(private="file")
Buffer :: struct
{
    buffer:     vk.Buffer,
    memory:     vk.DeviceMemory,
    length:     int,
    size:       vk.DeviceSize
}

@(private="file")
QueueFamily :: enum {
    Graphics,
    Present,
}

@(private="file")
QueueError :: enum {
    None,
    NoGraphicsBit,
}

@(private="file")
Swapchain :: struct {
    handle:         vk.SwapchainKHR,
    images:         []vk.Image,
    imageViews:     []vk.ImageView,
    format:         vk.SurfaceFormatKHR,
    extent:         vk.Extent2D,
    presentMode:    vk.PresentModeKHR,
    imageCount:     u32,
    support:        SwapchainDetails,
    framebuffers:   []vk.Framebuffer
}

@(private="file")
SwapchainDetails :: struct {
    capabilities:   vk.SurfaceCapabilitiesKHR,
    formats:        []vk.SurfaceFormatKHR,
    presentModes:   []vk.PresentModeKHR
}

@(private="file")
Pipeline :: struct {
    handle:     vk.Pipeline,
    renderPass: vk.RenderPass,
    layout:     vk.PipelineLayout,
}


// ███████ ███████ ████████ ██    ██ ██████  
// ██      ██         ██    ██    ██ ██   ██ 
// ███████ █████      ██    ██    ██ ██████  
//      ██ ██         ██    ██    ██ ██      
// ███████ ███████    ██     ██████  ██      
                                          

InitVulkan :: proc(using ctx: ^VulkanContext, vertices: []Vertex, indices: []u16)
{
    context.user_ptr = &instance
    get_proc_address :: proc(p:  rawptr, name: cstring)
    {
        (cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
    }

    vk.load_proc_addresses(get_proc_address)
    CreateInstance(ctx)
    vk.load_proc_addresses(get_proc_address)

    extensions := GetExtensions()
    when DETAILED_INFO {
        fmt.print("\n")
        LogInfo("Extensions:")
        for ext in &extensions do fmt.println(BytesToCstring(ext.extensionName))
    }

    CreateSurface(ctx)
    PickDevice(ctx)
    FindQueueFamilies(ctx)

    LogInfo("Queue Indices:")
    for q, f in queueIndices do fmt.printf(" %v: %d\n", f, q)

    CreateLogicalDevice(ctx)

    for &q, f in &queues
    {
        vk.GetDeviceQueue(device, u32(queueIndices[f]), 0, &q)
    }

    CreateSwapchain(ctx)
    CreateImageViews(ctx)
    CreateGraphicsPipeline(ctx, "shader.vert", "shader.frag")
    CreateFramebuffers(ctx)
    CreateCommandPool(ctx)
    CreateVertexBuffer(ctx, vertices)
    CreateIndexBuffer(ctx, indices)
    CreateCommandBuffers(ctx)
    CreateSyncObjects(ctx)
}

CleanupVulkan :: proc(using ctx: ^VulkanContext)
{
    vk.DeviceWaitIdle(device)
    CleanupSwapchain(ctx)

    vk.FreeMemory(device, indexBuffer.memory, nil)
    vk.DestroyBuffer(device, indexBuffer.buffer, nil)

    vk.FreeMemory(device, vertexBuffer.memory, nil)
    vk.DestroyBuffer(device, vertexBuffer.buffer, nil)

    vk.DestroyPipeline(device, pipeline.handle, nil)
    vk.DestroyPipelineLayout(device, pipeline.layout, nil)
    vk.DestroyRenderPass(device, pipeline.renderPass, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT
    {
        vk.DestroySemaphore(device, imageAvailable[i], nil)
        vk.DestroySemaphore(device, renderFinished[i], nil)
        vk.DestroyFence(device, inFlight[i], nil)
    }
    vk.DestroyCommandPool(device, commandPool, nil)

    vk.DestroyDevice(device, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)
}


// ██████  ██ ██████  ███████ ██      ██ ███    ██ ███████ 
// ██   ██ ██ ██   ██ ██      ██      ██ ████   ██ ██      
// ██████  ██ ██████  █████   ██      ██ ██ ██  ██ █████   
// ██      ██ ██      ██      ██      ██ ██  ██ ██ ██      
// ██      ██ ██      ███████ ███████ ██ ██   ████ ███████ 


CreateGraphicsPipeline :: proc(using ctx: ^VulkanContext, vsName: string, fsName: string)
{
    vsCode := CompileShader(vsName, .VertexShader)
    fsCode := CompileShader(fsName, .FragmentShader)

    defer
    {
        delete(vsCode)
        delete(fsCode)
    }

    vsShader := CreateShaderModule(ctx, vsCode)
    fsShader := CreateShaderModule(ctx, fsCode)
    defer
    {
        vk.DestroyShaderModule(device, vsShader, nil)
        vk.DestroyShaderModule(device, fsShader, nil)
    }

    vsInfo: vk.PipelineShaderStageCreateInfo
    vsInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    vsInfo.stage = {.VERTEX}
    vsInfo.module = vsShader
    vsInfo.pName = "main"

    fsInfo: vk.PipelineShaderStageCreateInfo
    fsInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    fsInfo.stage = {.FRAGMENT}
    fsInfo.module = fsShader
    fsInfo.pName = "main"

    shaderStages := [?]vk.PipelineShaderStageCreateInfo{vsInfo, fsInfo}

    dynamicStates := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dynamicState: vk.PipelineDynamicStateCreateInfo
    dynamicState.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
    dynamicState.dynamicStateCount = len(dynamicStates)
    dynamicState.pDynamicStates = &dynamicStates[0]

    vertexInput: vk.PipelineVertexInputStateCreateInfo
    vertexInput.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    vertexInput.vertexBindingDescriptionCount = 1
    vertexInput.pVertexBindingDescriptions = &VERTEX_BINDING
    vertexInput.vertexAttributeDescriptionCount = len(VERTEX_ATTRIBUTES)
    vertexInput.pVertexAttributeDescriptions = &VERTEX_ATTRIBUTES[0]

    inputAssembly: vk.PipelineInputAssemblyStateCreateInfo
    inputAssembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    inputAssembly.topology = .TRIANGLE_LIST
    inputAssembly.primitiveRestartEnable = false

    viewport: vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = cast(f32)swapchain.extent.width
    viewport.height = cast(f32)swapchain.extent.height
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0

    scissor: vk.Rect2D
    scissor.offset = {0, 0}
    scissor.extent = swapchain.extent

    viewportState: vk.PipelineViewportStateCreateInfo
    viewportState.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
    viewportState.viewportCount = 1
    viewportState.scissorCount = 1

    rasterizer: vk.PipelineRasterizationStateCreateInfo
    rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    rasterizer.depthClampEnable = false
    rasterizer.rasterizerDiscardEnable = false
    rasterizer.polygonMode = .FILL
    rasterizer.lineWidth = 1.0
    rasterizer.cullMode = {.BACK}
    rasterizer.frontFace = .CLOCKWISE
    rasterizer.depthBiasEnable = false
    rasterizer.depthBiasConstantFactor = 0.0
    rasterizer.depthBiasClamp = 0.0
    rasterizer.depthBiasSlopeFactor = 0.0

    multisampling: vk.PipelineMultisampleStateCreateInfo
    multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    multisampling.sampleShadingEnable = false
    multisampling.rasterizationSamples = {._1}
    multisampling.minSampleShading = 1.0
    multisampling.pSampleMask = nil
    multisampling.alphaToCoverageEnable = false
    multisampling.alphaToOneEnable = false

    colorBlendAttachment: vk.PipelineColorBlendAttachmentState
    colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
    colorBlendAttachment.blendEnable = true
    colorBlendAttachment.srcColorBlendFactor = .SRC_ALPHA
    colorBlendAttachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
    colorBlendAttachment.colorBlendOp = .ADD
    colorBlendAttachment.srcAlphaBlendFactor = .ONE
    colorBlendAttachment.dstAlphaBlendFactor = .ZERO
    colorBlendAttachment.alphaBlendOp  = .ADD

    colorBlending: vk.PipelineColorBlendStateCreateInfo
    colorBlending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    colorBlending.logicOpEnable = false
    colorBlending.logicOp = .COPY
    colorBlending.attachmentCount = 1
    colorBlending.pAttachments = &colorBlendAttachment
    colorBlending.blendConstants[0] = 0.0
    colorBlending.blendConstants[1] = 0.0
    colorBlending.blendConstants[2] = 0.0
    colorBlending.blendConstants[3] = 0.0

    pipelineLayoutInfo: vk.PipelineLayoutCreateInfo
    pipelineLayoutInfo.sType = .PIPELINE_LAYOUT_CREATE_INFO
    pipelineLayoutInfo.setLayoutCount = 0
    pipelineLayoutInfo.pSetLayouts = nil
    pipelineLayoutInfo.pushConstantRangeCount = 0
    pipelineLayoutInfo.pPushConstantRanges = nil

    if res := vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &pipeline.layout); res != .SUCCESS {
        LogError("Failed to create Pipeline Layout!\n")
        os.exit(1)
    }

    CreateRenderPass(ctx)

    pipelineInfo: vk.GraphicsPipelineCreateInfo
    pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
    pipelineInfo.stageCount = 2
    pipelineInfo.pStages = &shaderStages[0]
    pipelineInfo.pVertexInputState = &vertexInput
    pipelineInfo.pInputAssemblyState = &inputAssembly
    pipelineInfo.pViewportState = &viewportState
    pipelineInfo.pRasterizationState = &rasterizer
    pipelineInfo.pMultisampleState = &multisampling
    pipelineInfo.pDepthStencilState = nil
    pipelineInfo.pColorBlendState = &colorBlending
    pipelineInfo.pDynamicState = &dynamicState
    pipelineInfo.layout = pipeline.layout
    pipelineInfo.renderPass = pipeline.renderPass
    pipelineInfo.subpass = 0
    pipelineInfo.basePipelineHandle = vk.Pipeline{}
    pipelineInfo.basePipelineIndex = -1

    if res := vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline.handle); res != .SUCCESS {
        LogError("Failed to create Graphics Pipeline!\n")
        os.exit(1)
    }
}


// ██████  ███████ ███    ██ ██████  ███████ ██████  ██████   █████  ███████ ███████ 
// ██   ██ ██      ████   ██ ██   ██ ██      ██   ██ ██   ██ ██   ██ ██      ██      
// ██████  █████   ██ ██  ██ ██   ██ █████   ██████  ██████  ███████ ███████ ███████ 
// ██   ██ ██      ██  ██ ██ ██   ██ ██      ██   ██ ██      ██   ██      ██      ██ 
// ██   ██ ███████ ██   ████ ██████  ███████ ██   ██ ██      ██   ██ ███████ ███████


CreateRenderPass :: proc(using ctx: ^VulkanContext)
{
    colorAttachment: vk.AttachmentDescription
    colorAttachment.format = swapchain.format.format
    colorAttachment.samples = {._1}
    colorAttachment.loadOp = .CLEAR
    colorAttachment.storeOp = .STORE
    colorAttachment.stencilLoadOp = .DONT_CARE
    colorAttachment.stencilStoreOp = .DONT_CARE
    colorAttachment.initialLayout = .UNDEFINED
    colorAttachment.finalLayout = .PRESENT_SRC_KHR

    colorAttachmentRef: vk.AttachmentReference
    colorAttachmentRef.attachment = 0
    colorAttachmentRef.layout = .COLOR_ATTACHMENT_OPTIMAL

    subpass: vk.SubpassDescription
    subpass.pipelineBindPoint = .GRAPHICS
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = &colorAttachmentRef

    dependency: vk.SubpassDependency
    dependency.srcSubpass = vk.SUBPASS_EXTERNAL
    dependency.dstSubpass = 0
    dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT}
    dependency.srcAccessMask = {}
    dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
    dependency.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}

    renderPassInfo: vk.RenderPassCreateInfo
    renderPassInfo.sType = .RENDER_PASS_CREATE_INFO
    renderPassInfo.attachmentCount = 1
    renderPassInfo.pAttachments = &colorAttachment
    renderPassInfo.subpassCount = 1
    renderPassInfo.pSubpasses = &subpass
    renderPassInfo.dependencyCount = 1
    renderPassInfo.pDependencies = &dependency

    if res := vk.CreateRenderPass(device, &renderPassInfo, nil, &pipeline.renderPass); res != .SUCCESS {
        LogError("Failed to create Render Pass!\n")
        os.exit(1)
    }
}

CompileShader :: proc(name: string, kind: shaderc.shaderKind) -> []u8
{
    srcPath := fmt.tprintf("./shaders/%s", name)
    cmpPath := fmt.tprintf("./shaders/compiled/%s.spv", name)
    srcTime, srcErr := os.last_write_time_by_name(srcPath)
    if srcErr != os.ERROR_NONE{
        LogError(fmt.tprintf("Failed to open shader %q\n", srcPath))
        return nil
    }

    cmpTime, cmpErr := os.last_write_time_by_name(cmpPath)
    if cmpErr != os.ERROR_NONE && cmpTime >= srcTime{
        code, _ := os.read_entire_file(cmpPath)
        return code
    }

    comp := shaderc.compiler_initialize()
    options := shaderc.compile_options_initialize()
    defer
    {
        shaderc.compiler_release(comp)
        shaderc.compile_options_release(options)
    }

    shaderc.compile_options_set_optimization_level(options, .Performance)

    code, _ := os.read_entire_file(srcPath)
    cPath := strings.clone_to_cstring(srcPath, context.temp_allocator)
    res := shaderc.compile_into_spv(comp, cstring(raw_data(code)), len(code), kind, cPath, cstring("main"), options)
    defer shaderc.result_release(res)

    status := shaderc.result_get_compilation_status(res)
    if status != .Success{
        fmt.printf("%s: Error: %s\n", name, shaderc.result_get_error_message(res))
        return nil
    }

    length := shaderc.result_get_length(res)
    out := make([]u8, length)
    cOut := shaderc.result_get_bytes(res)
    mem.copy(raw_data(out), cOut, int(length))
    os.write_entire_file(cmpPath, out)

    return out
}

CreateShaderModule :: proc(using ctx: ^VulkanContext, code: []u8) -> vk.ShaderModule
{
    createInfo: vk.ShaderModuleCreateInfo
    createInfo.sType = .SHADER_MODULE_CREATE_INFO
    createInfo.codeSize = len(code)
    createInfo.pCode = cast(^u32)raw_data(code)

    shader: vk.ShaderModule
    if res := vk.CreateShaderModule(device, &createInfo, nil, &shader); res != .SUCCESS {
        LogError("Could not create Shader Module!\n")
        os.exit(1)
    }

    return shader
}


// ██████  ██    ██ ███████ ███████ ███████ ██████  
// ██   ██ ██    ██ ██      ██      ██      ██   ██ 
// ██████  ██    ██ █████   █████   █████   ██████  
// ██   ██ ██    ██ ██      ██      ██      ██   ██ 
// ██████   ██████  ██      ██      ███████ ██   ██ 


CreateCommandPool :: proc(using ctx: ^VulkanContext)
{
    poolInfo: vk.CommandPoolCreateInfo
    poolInfo.sType = .COMMAND_POOL_CREATE_INFO
    poolInfo.flags = {.RESET_COMMAND_BUFFER}
    poolInfo.queueFamilyIndex = u32(queueIndices[.Graphics])

    if res := vk.CreateCommandPool(device, &poolInfo, nil, &commandPool); res != .SUCCESS {
        LogError("Failed to create Command Pool!\n")
        os.exit(1)
    }
}

CreateCommandBuffers :: proc(using ctx: ^VulkanContext)
{
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = commandPool
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = len(commandBuffers)

    if res := vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffers[0]); res != .SUCCESS {
        LogError("Failed to allocate command buffers!\n")
        os.exit(1)
    }
}

RecordCommandBuffer :: proc(using ctx: ^VulkanContext, buffer: vk.CommandBuffer, imageIndex: u32)
{
    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.flags = {}
    beginInfo.pInheritanceInfo = nil
    
    if res := vk.BeginCommandBuffer(buffer, &beginInfo); res != .SUCCESS {
        LogError("Failed to begin recording Command Buffer!\n")
        os.exit(1)
    }

    renderPassInfo: vk.RenderPassBeginInfo
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = pipeline.renderPass
    renderPassInfo.framebuffer = swapchain.framebuffers[imageIndex]
    renderPassInfo.renderArea.offset = {0, 0}
    renderPassInfo.renderArea.extent = swapchain.extent

    clearColor: vk.ClearValue
    clearColor.color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
    renderPassInfo.clearValueCount = 1
    renderPassInfo.pClearValues = &clearColor

    vk.CmdBeginRenderPass(buffer, &renderPassInfo, .INLINE)

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline.handle)

    vertexBuffers := [?]vk.Buffer{vertexBuffer.buffer}
    offsets := [?]vk.DeviceSize{0}
    vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
    vk.CmdBindIndexBuffer(buffer, indexBuffer.buffer, 0, .UINT16)

    viewport: vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = f32(swapchain.extent.width)
    viewport.height = f32(swapchain.extent.height)
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0
    vk.CmdSetViewport(buffer, 0, 1, &viewport)

    scissor: vk.Rect2D
    scissor.offset = {0, 0}
    scissor.extent = swapchain.extent
    vk.CmdSetScissor(buffer, 0, 1, &scissor)

    vk.CmdDrawIndexed(buffer, cast(u32)indexBuffer.length, 1, 0, 0, 0)

    vk.CmdEndRenderPass(buffer)

    if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
        LogError("Failed to record Command Buffer!\n")
        os.exit(1)
    }    
}

FindMemoryType :: proc(using ctx: ^VulkanContext, typeFilter: u32, properties: vk.MemoryPropertyFlags) -> u32
{
    memProps: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(physicalDevice, &memProps)
    for i in 0..<memProps.memoryTypeCount
    {
        if (typeFilter & (1 << i) != 0) && (memProps.memoryTypes[i].propertyFlags & properties) == properties {
            return i
        }
    }

    LogError("Failed to find usable memory type!\n")
    os.exit(1)
}

CreateBuffer :: proc(using ctx: ^VulkanContext, memberSize: int, count: int, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, buffer: ^Buffer)
{
    bufferInfo := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = cast(vk.DeviceSize)(memberSize * count),
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }

    if res := vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer); res != .SUCCESS {
        LogError("Failed to create Buffer!\n")
        os.exit(1)
    }

    memReqs: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(device, buffer.buffer, &memReqs)

    allocInfo := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memReqs.size,
        memoryTypeIndex = FindMemoryType(ctx, memReqs.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT})
    }

    if res := vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory); res != .SUCCESS {
        LogError("Failed to allocate Buffer Memory!\n")
        os.exit(1)
    }

    vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0)
}

CopyBuffer :: proc(using ctx: ^VulkanContext, src, dst: Buffer, size: vk.DeviceSize)
{
    allocInfo := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = commandPool,
        commandBufferCount = 1,
    }

    cmdBuffer: vk.CommandBuffer
    vk.AllocateCommandBuffers(device, &allocInfo, &cmdBuffer)

    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }

    vk.BeginCommandBuffer(cmdBuffer, &beginInfo)

    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }
    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
    vk.EndCommandBuffer(cmdBuffer)

    submitInfo := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &cmdBuffer,
    }

    vk.QueueSubmit(queues[.Graphics], 1, &submitInfo, {})
    vk.QueueWaitIdle(queues[.Graphics])
    vk.FreeCommandBuffers(device, commandPool, 1, &cmdBuffer)
}

CreateVertexBuffer :: proc(using ctx: ^VulkanContext, vertices: []Vertex)
{
    vertexBuffer.length = len(vertices)
    vertexBuffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))

    staging: Buffer
    CreateBuffer(ctx, size_of(Vertex), len(vertices), {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging)

    data: rawptr
    vk.MapMemory(device, staging.memory, 0, vertexBuffer.size, {}, &data)
    mem.copy(data, raw_data(vertices), cast(int)vertexBuffer.size)
    vk.UnmapMemory(device, staging.memory)

    CreateBuffer(ctx, size_of(Vertex), len(vertices), {.VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &vertexBuffer)
    CopyBuffer(ctx, staging, vertexBuffer, vertexBuffer.size)

    vk.FreeMemory(device, staging.memory, nil)
    vk.DestroyBuffer(device, staging.buffer, nil)
}

CreateIndexBuffer :: proc(using ctx: ^VulkanContext, indices: []u16)
{
    indexBuffer.length = len(indices)
    indexBuffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

    staging: Buffer
    CreateBuffer(ctx, size_of(indices[0]), len(indices), {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging)

    data: rawptr
    vk.MapMemory(device, staging.memory, 0, indexBuffer.size, {}, &data)
    mem.copy(data, raw_data(indices), cast(int)indexBuffer.size)
    vk.UnmapMemory(device, staging.memory)

    CreateBuffer(ctx, size_of(Vertex), len(indices), {.INDEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &indexBuffer)
    CopyBuffer(ctx, staging, indexBuffer, indexBuffer.size)

    vk.FreeMemory(device, staging.memory, nil)
    vk.DestroyBuffer(device, staging.buffer, nil)
}

CreateSyncObjects :: proc(using ctx: ^VulkanContext)
{
    semaphoreInfo: vk.SemaphoreCreateInfo
    semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

    fenceInfo: vk.FenceCreateInfo
    fenceInfo.sType = .FENCE_CREATE_INFO
    fenceInfo.flags = {.SIGNALED}

    for i in 0..<MAX_FRAMES_IN_FLIGHT
    {
        res := vk.CreateSemaphore(device, &semaphoreInfo, nil, &imageAvailable[i])
        if res != .SUCCESS{
            LogError("Failed to create \"imageAvailable\" Semaphore!\n")
            os.exit(1)
        }
        res = vk.CreateSemaphore(device, &semaphoreInfo, nil, &renderFinished[i])
        if res != .SUCCESS{
            LogError("Failed to create \"renderFinished\" Semaphore!\n")
            os.exit(1)
        }
        res = vk.CreateFence(device, &fenceInfo, nil, &inFlight[i])
        if res != .SUCCESS{
            LogError("Failed to create \"inFlight\" Fence!\n")
            os.exit(1)
        }
    }
}


// ██████  ██████   █████  ██     ██ 
// ██   ██ ██   ██ ██   ██ ██     ██ 
// ██   ██ ██████  ███████ ██  █  ██ 
// ██   ██ ██   ██ ██   ██ ██ ███ ██ 
// ██████  ██   ██ ██   ██  ███ ███  


DrawFrame :: proc(using ctx: ^VulkanContext, vertices: []Vertex, indices: []u16)
{
    vk.WaitForFences(device, 1, &inFlight[curFrame], true, max(u64))
    
    imageIndex: u32

    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), imageAvailable[curFrame], {}, &imageIndex)
    if res == .ERROR_OUT_OF_DATE_KHR {
        RecreateSwapchain(ctx)
        return
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        LogError("Failed to acquire Swapchain Image!\n")
        os.exit(1)
    }

    vk.ResetFences(device, 1, &inFlight[curFrame])
    vk.ResetCommandBuffer(commandBuffers[curFrame], {})
    RecordCommandBuffer(ctx, commandBuffers[curFrame], imageIndex)

    submitInfo: vk.SubmitInfo
    submitInfo.sType = .SUBMIT_INFO

    waitSemaphores := [?]vk.Semaphore{imageAvailable[curFrame]}
    waitStages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
    submitInfo.waitSemaphoreCount = 1
    submitInfo.pWaitSemaphores = &waitSemaphores[0]
    submitInfo.pWaitDstStageMask = &waitStages[0]
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = &commandBuffers[curFrame]

    signalSemaphores := [?]vk.Semaphore{renderFinished[curFrame]}
    submitInfo.signalSemaphoreCount = 1
    submitInfo.pSignalSemaphores = &signalSemaphores[0]

    if res := vk.QueueSubmit(queues[.Graphics], 1, &submitInfo, inFlight[curFrame]); res != .SUCCESS {
        LogError("Failed to submit Draw Command Buffer!\n")
        os.exit(1)
    }

    presentInfo: vk.PresentInfoKHR
    presentInfo.sType = .PRESENT_INFO_KHR
    presentInfo.waitSemaphoreCount = 1
    presentInfo.pWaitSemaphores = &signalSemaphores[0]

    swapchains := [?]vk.SwapchainKHR{swapchain.handle}
    presentInfo.swapchainCount = 1
    presentInfo.pSwapchains = &swapchains[0]
    presentInfo.pImageIndices = &imageIndex
    presentInfo.pResults = nil

    res = vk.QueuePresentKHR(queues[.Present], &presentInfo)
    if (res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || framebufferResized) {
        framebufferResized = false
        RecreateSwapchain(ctx)
    } else if res != .SUCCESS {
        LogError("Failed to present Swapchain Image!\n")
        os.exit(1)
    }
    curFrame = (curFrame + 1) % MAX_FRAMES_IN_FLIGHT
}


// ██       ██       ██       ██       ██       ██       
//  ██       ██       ██       ██       ██       ██      
//   ██       ██       ██       ██       ██       ██     
//  ██       ██       ██       ██       ██       ██      
// ██       ██       ██       ██       ██       ██       


CheckValidationLayerSupport :: proc(using ctx: ^VulkanContext) -> bool
{
    layerCount: u32
    vk.EnumerateInstanceLayerProperties(&layerCount, nil)
    layers := make([]vk.LayerProperties, layerCount)
    vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(layers))

    when DETAILED_INFO {
        LogInfo("Layers:")
        for props in layers
        {
            fmt.println(BytesToString(props.layerName))
            fmt.println(BytesToString(props.description))
            fmt.print("\n")
        }
    }

    for name in VALIDATION_LAYERS
    {
        layerFound := false
        for props in layers
        {
            if name == BytesToCstring(props.layerName) {
                layerFound = true
                break
            }
        }

        if !layerFound {
            LogError(fmt.tprint("Validation Layer %q not available!", name))
            return false
        }
    }

    return true
}

CheckDeviceExtensionSupport :: proc(physDevice: vk.PhysicalDevice) -> bool
{
    extensionCount: u32;
    vk.EnumerateDeviceExtensionProperties(physDevice, nil, &extensionCount, nil)

    availableExtensions := make([]vk.ExtensionProperties, extensionCount)
    vk.EnumerateDeviceExtensionProperties(physDevice, nil, &extensionCount, raw_data(availableExtensions))

    for ext in DEVICE_EXTENSIONS
    {
        found: b32
        for available in &availableExtensions
        {
            if BytesToCstring(available.extensionName) == ext{
                found = true
                break
            }
        }
        if !found do return false
    }
    return true
}

GetExtensions :: proc() -> []vk.ExtensionProperties
{
    extensionCount: u32
    vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
    extensions := make([]vk.ExtensionProperties, extensionCount)
    vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, raw_data(extensions))

    return extensions
}

CreateInstance :: proc(using ctx: ^VulkanContext)
{
    appInfo: vk.ApplicationInfo
    appInfo.sType = .APPLICATION_INFO
    appInfo.pApplicationName = "Tonkatsu Triangle Triads"
    appInfo.applicationVersion = vk.MAKE_VERSION(0, 0, 1)
    appInfo.pEngineName = "Tonkatsu Triangle Triads"
    appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
    appInfo.apiVersion = vk.API_VERSION_1_4

    createInfo: vk.InstanceCreateInfo
    createInfo.sType = .INSTANCE_CREATE_INFO
    createInfo.pApplicationInfo = &appInfo
    glfwExtensions := glfw.GetRequiredInstanceExtensions()
    createInfo.ppEnabledExtensionNames = raw_data(glfwExtensions)
    createInfo.enabledExtensionCount = u32(len(glfwExtensions))

    if (vk.CreateInstance(&createInfo, nil, &instance) != .SUCCESS) {
        LogError("Failed to create Instance!\n")
        return
    }

    if (enableValidationLayers && !CheckValidationLayerSupport(ctx)) {
        LogError("Validation Layers requested, but not available!")
        os.exit(1)
    }

    if enableValidationLayers {
        createInfo.enabledLayerCount = len(VALIDATION_LAYERS)
        createInfo.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
        LogInfo("Validation Layers loaded")
    } else {
        createInfo.enabledLayerCount = 0
        when DETAILED_INFO {
            layerCount: u32
            vk.EnumerateInstanceLayerProperties(&layerCount, nil)
            layers := make([]vk.LayerProperties, layerCount)
            vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(layers))
            LogInfo("Layers:")
            for props in layers
            {
                fmt.println(BytesToString(props.layerName))
                fmt.println(BytesToString(props.description))
                fmt.print("\n")
            }
        }
    }

    if (vk.CreateInstance(&createInfo, nil, &instance) != .SUCCESS) {
        LogError("Failed to create Instance!\n")
        return
    }

    LogInfo("Instance created")
}

CreateSurface :: proc(using ctx: ^VulkanContext)
{
    if res := glfw.CreateWindowSurface(instance, window, nil, &surface); res != .SUCCESS{
        LogError("Failed to create window surface!\n")
        os.exit(1)
    }
}

CreateLogicalDevice :: proc(using ctx: ^VulkanContext)
{
    uniqueIndices: map[int]b8
    defer delete(uniqueIndices)
    for i in queueIndices do uniqueIndices[i] = true

    queuePriority := f32(1.0)

    queueCreateInfos: [dynamic]vk.DeviceQueueCreateInfo
    defer delete(queueCreateInfos)
    for k, _ in uniqueIndices
    {
        queueCreateInfo: vk.DeviceQueueCreateInfo
        queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
        queueCreateInfo.queueFamilyIndex = u32(queueIndices[.Graphics])
        queueCreateInfo.queueCount = 1
        queueCreateInfo.pQueuePriorities = &queuePriority
        append(&queueCreateInfos, queueCreateInfo)
    }

    enabledFeatures: vk.PhysicalDeviceFeatures

    deviceCreateInfo: vk.DeviceCreateInfo
    deviceCreateInfo.sType = .DEVICE_CREATE_INFO
    deviceCreateInfo.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS))
    deviceCreateInfo.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
    deviceCreateInfo.queueCreateInfoCount = u32(len(queueCreateInfos))
    deviceCreateInfo.pQueueCreateInfos = raw_data(queueCreateInfos)
    deviceCreateInfo.pEnabledFeatures = &enabledFeatures
    deviceCreateInfo.enabledLayerCount = 0

    if res := vk.CreateDevice(physicalDevice, &deviceCreateInfo, nil, &device); res != .SUCCESS {
        LogError("Failed to create Logical Device!")
        os.exit(1)
    }
}

CreateImageViews :: proc(using ctx: ^VulkanContext)
{
    using ctx.swapchain

    imageViews = make([]vk.ImageView, len(images))

    for _, i in images
    {
        createInfo: vk.ImageViewCreateInfo
        createInfo.sType = .IMAGE_VIEW_CREATE_INFO
        createInfo.image = images[i]
        createInfo.viewType = .D2
        createInfo.format = format.format
        createInfo.components.r = .IDENTITY
        createInfo.components.g = .IDENTITY
        createInfo.components.b = .IDENTITY
        createInfo.components.a = .IDENTITY
        createInfo.subresourceRange.aspectMask = {.COLOR}
        createInfo.subresourceRange.baseMipLevel = 0
        createInfo.subresourceRange.levelCount = 1
        createInfo.subresourceRange.baseArrayLayer = 0
        createInfo.subresourceRange.layerCount = 1

        if res := vk.CreateImageView(device, &createInfo, nil, &imageViews[i]); res != .SUCCESS {
            LogError("Failed to create Image View!")
            os.exit(1)
        }
    }
}

QuerySwapchainDetails :: proc(using ctx: ^VulkanContext, dev: vk.PhysicalDevice)
{
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swapchain.support.capabilities)

    formatCount: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &formatCount, nil)
    if formatCount > 0 {
        swapchain.support.formats = make([]vk.SurfaceFormatKHR, formatCount)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &formatCount, raw_data(swapchain.support.formats))
    }

    presentModeCount: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &presentModeCount, nil)
    if presentModeCount > 0 {
        swapchain.support.presentModes = make([]vk.PresentModeKHR, presentModeCount)
        vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &presentModeCount, raw_data(swapchain.support.presentModes))
    }
}


// ███████ ██     ██  █████  ██████   ██████ ██   ██  █████  ██ ███    ██ 
// ██      ██     ██ ██   ██ ██   ██ ██      ██   ██ ██   ██ ██ ████   ██ 
// ███████ ██  █  ██ ███████ ██████  ██      ███████ ███████ ██ ██ ██  ██ 
//      ██ ██ ███ ██ ██   ██ ██      ██      ██   ██ ██   ██ ██ ██  ██ ██ 
// ███████  ███ ███  ██   ██ ██       ██████ ██   ██ ██   ██ ██ ██   ████ 


CreateSwapchain :: proc(using ctx: ^VulkanContext)
{
    using ctx.swapchain.support
    swapchain.format        = ChooseSurfaceFormat(ctx)
    swapchain.presentMode   = ChoosePresentMode(ctx)
    swapchain.extent        = ChooseSwapExtent(ctx)
    swapchain.imageCount    = capabilities.minImageCount + 1

    if capabilities.maxImageCount > 0 && swapchain.imageCount > capabilities.maxImageCount{
        swapchain.imageCount = capabilities.maxImageCount
    }

    createInfo: vk.SwapchainCreateInfoKHR
    createInfo.sType = .SWAPCHAIN_CREATE_INFO_KHR
    createInfo.surface = surface
    createInfo.minImageCount = swapchain.imageCount
    createInfo.imageFormat = swapchain.format.format
    createInfo.imageColorSpace = swapchain.format.colorSpace
    createInfo.imageExtent = swapchain.extent
    createInfo.imageArrayLayers = 1
    createInfo.imageUsage = {.COLOR_ATTACHMENT}

    queueFamilyIndices := [len(QueueFamily)]u32{u32(queueIndices[.Graphics]), u32(queueIndices[.Present])}

    if queueIndices[.Graphics] != queueIndices[.Present] {
        createInfo.imageSharingMode = .CONCURRENT
        createInfo.queueFamilyIndexCount = 2
        createInfo.pQueueFamilyIndices = &queueFamilyIndices[0]      
    } else {
        createInfo.imageSharingMode = .EXCLUSIVE
        createInfo.queueFamilyIndexCount = 0
        createInfo.pQueueFamilyIndices = nil
    }

    createInfo.preTransform = capabilities.currentTransform
    createInfo.compositeAlpha = {.OPAQUE}
    createInfo.presentMode = swapchain.presentMode
    createInfo.clipped = true
    createInfo.oldSwapchain = vk.SwapchainKHR{}

    if res := vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain.handle); res != .SUCCESS {
        LogError("Failed to create Swapchain!\n")
        os.exit(1)
    }

    vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.imageCount, nil)
    swapchain.images = make([]vk.Image, swapchain.imageCount)
    vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.imageCount, raw_data(swapchain.images))
}

RecreateSwapchain :: proc(using ctx: ^VulkanContext)
{
    width, height: i32 = 0, 0
    width, height = glfw.GetFramebufferSize(window)
    for width == 0 || height == 0
    {
        glfw.WaitEvents()
        width, height = glfw.GetFramebufferSize(window)
    }
    vk.DeviceWaitIdle(device)

    CleanupSwapchain(ctx)

    QuerySwapchainDetails(ctx, physicalDevice)

    CreateSwapchain(ctx)

    if (swapchain.format != oldSwapchain.format) {
        vk.DestroyRenderPass(device, pipeline.renderPass, nil)
        CreateRenderPass(ctx)
    }

    CreateImageViews(ctx)
    CreateFramebuffers(ctx)
}

CleanupSwapchain :: proc(using ctx: ^VulkanContext)
{
    for f in swapchain.framebuffers
    {
        vk.DestroyFramebuffer(device, f, nil)
    }
    for view in swapchain.imageViews
    {
        vk.DestroyImageView(device, view, nil)
    }
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

CreateFramebuffers :: proc(using ctx: ^VulkanContext)
{
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.imageViews))
    for v, i in swapchain.imageViews
    {
        attachments := [?]vk.ImageView{v}

        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = pipeline.renderPass
        framebufferInfo.attachmentCount = 1
        framebufferInfo.pAttachments = &attachments[0]
        framebufferInfo.width = swapchain.extent.width
        framebufferInfo.height = swapchain.extent.height
        framebufferInfo.layers = 1

        if res := vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapchain.framebuffers[i]); res != .SUCCESS {
            LogError(fmt.tprintf("Failed to create Framebuffer%d\n", i))
            os.exit(1)
        }
    }
}

//MAYBE: Make multiple GPUs usable?
PickDevice :: proc(using ctx: ^VulkanContext)
{
    deviceCount: u32

    vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)
    if deviceCount == 0 {
        LogError("Failed to find GPUs with Vulkan support!\n")
        os.exit(1)
    }

    devices := make([]vk.PhysicalDevice, deviceCount)
    vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(devices))

    RateSuitability :: proc(using ctx: ^VulkanContext, dev: vk.PhysicalDevice, idx: int) -> int
    {
        properties: vk.PhysicalDeviceProperties
        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(dev, &properties)
        vk.GetPhysicalDeviceFeatures(dev, &features)

        LogInfo(fmt.tprintf("GPU%d: %s", idx, properties.deviceName))

        score := 0
        if properties.deviceType == .DISCRETE_GPU do score += 1000
        score += int(properties.limits.maxImageDimension2D)

        if !features.geometryShader do return 0
        if !CheckDeviceExtensionSupport(dev) do return 0

        QuerySwapchainDetails(ctx, dev)
        if len(swapchain.support.formats) == 0 || len(swapchain.support.presentModes) == 0 do return 0

        return score
    }

    hiscore := 0
    LogInfo(fmt.tprintf("Found %d GPU(s)", len(devices)))
    idx := 0
    for dev in devices
    {
        score := RateSuitability(ctx, dev, idx)
        if score > hiscore{
            physicalDevice = dev
            hiscore = score
        }
        idx += 1
    }

    if hiscore == 0{
        LogError("Failed to find suitable GPU!\n")
        os.exit(1)
    }

    properties: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(physicalDevice, &properties)
    ctx.physicalDeviceProps = properties
    LogInfo(fmt.tprintf("Using GPU: %s", properties.deviceName))
    when DETAILED_INFO {
        LogInfo(fmt.tprintf("Driver Version: %d", properties.driverVersion))
    }
}

FindQueueFamilies :: proc(using ctx: ^VulkanContext)
{
    queueCount: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, nil)
    availableQueues := make([]vk.QueueFamilyProperties, queueCount)
    vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, raw_data(availableQueues))

    for v, i in availableQueues
    {
        if .GRAPHICS in v.queueFlags && queueIndices[.Graphics] == -1 do queueIndices[.Graphics] = i

        presentSupport: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(physicalDevice, u32(i), surface, &presentSupport)
        if presentSupport && queueIndices[.Present] == -1 do queueIndices[.Present] = i

        for q in queueIndices do if q == -1 do continue
        break
    }
}

ChooseSurfaceFormat :: proc(using ctx: ^VulkanContext) -> vk.SurfaceFormatKHR
{
    for v in swapchain.support.formats
    {
        if v.format == .B8G8R8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
    }

    return swapchain.support.formats[0]
}

ChoosePresentMode :: proc(using ctx: ^VulkanContext) -> vk.PresentModeKHR
{
    // Prefer Mailbox, otherwise default to FIFO
    for v in swapchain.support.presentModes
    {
        if v == .MAILBOX do return v
    }

    return .FIFO
}

ChooseSwapExtent :: proc(using ctx: ^VulkanContext) -> vk.Extent2D
{
    // Provide for case 0xFFFFFFFF:
    if (swapchain.support.capabilities.currentExtent.width != max(u32))
    {
        return swapchain.support.capabilities.currentExtent
    } else {
        width, height := glfw.GetFramebufferSize(window)

        extent := vk.Extent2D{u32(width), u32(height)}

        extent.width = clamp(extent.width, swapchain.support.capabilities.minImageExtent.width, swapchain.support.capabilities.maxImageExtent.width)
        extent.height = clamp(extent.height, swapchain.support.capabilities.minImageExtent.height, swapchain.support.capabilities.maxImageExtent.height)
        
        return extent
    }
}


// ██    ██ ████████ ██ ██      
// ██    ██    ██    ██ ██      
// ██    ██    ██    ██ ██      
// ██    ██    ██    ██ ██      
//  ██████     ██    ██ ███████ 


BytesToCstring :: proc (bytes: [256]u8) -> cstring
{
    bytess: [256]u8 = bytes
    str := strings.clone_from_bytes(bytess[:])
    cstr := strings.clone_to_cstring(str)
    return cstr
}

BytesToString :: proc (bytes: [256]u8) -> string
{
    bytess: [256]u8 = bytes
    str := strings.clone_from_bytes(bytess[:])
    return str
}