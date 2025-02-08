package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import m "core:math"
import glm "core:math/linalg/glsl"
import "vendor:glfw"
import vk "vendor:vulkan"
import stbi "vendor:stb/image"
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
DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_dynamic_rendering", "VK_KHR_swapchain"};


// ███████ ███████ ████████ ██    ██ ██████  
// ██      ██         ██    ██    ██ ██   ██ 
// ███████ █████      ██    ██    ██ ██████  
//      ██ ██         ██    ██    ██ ██      
// ███████ ███████    ██     ██████  ██     


InitVulkanDR :: proc(using ctx: ^VulkanContext,  vertices: []Vertex, indices: []u32)
{
    context.user_ptr = &instance
    get_proc_address :: proc(p:  rawptr, name: cstring)
    {
        (cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
    }

    msaaSamples = vk.SampleCountFlag._1
    mipLevels = 1

    vk.load_proc_addresses(get_proc_address)
    CreateInstanceDR(ctx)
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
    CreateLogicalDeviceDR(ctx)

    for &q, f in &queues
    {
        vk.GetDeviceQueue(device, u32(queueIndices[f]), 0, &q)
    }

    CreateSwapchainDR(ctx)
    CreateImageViews(ctx)
    CreateDescriptorSetLayout(ctx)
    CreateGraphicsPipelineDR(ctx, "vert", "frag")
    CreateCommandPool(ctx)
    if MSAA_ENABLED {
        CreateColorResources(ctx)
    }
    CreateDepthResources(ctx)
    // CreateFramebuffers(ctx)
    CreateTextureImage(ctx)
    CreateTextureImageView(ctx)
    CreateTextureSampler(ctx)
    CreateVertexBuffer(ctx, vertices)
    CreateIndexBuffer(ctx, indices)
    CreateUniformBuffers(ctx)
    CreateDescriptorPool(ctx)
    CreateDescriptorSets(ctx)
    CreateCommandBuffers(ctx)
    CreateSyncObjects(ctx)
}

CleanupVulkanDR :: proc(using ctx: ^VulkanContext)
{
    vk.DeviceWaitIdle(device)
    CleanupSwapchainDR(ctx)

    vk.DestroySampler(device, textureSampler, nil)
    vk.DestroyImageView(device, textureImageView, nil)
    vk.DestroyImage(device, textureImage.image, nil)
    vk.FreeMemory(device, textureImage.memory, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT
    {
        vk.DestroyBuffer(device, uniformBuffers[i].buffer, nil)
        vk.FreeMemory(device, uniformBuffers[i].memory, nil)
    }

    vk.DestroyDescriptorPool(device, descriptorPool, nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayout, nil)

    vk.FreeMemory(device, indexBuffer.memory, nil)
    vk.DestroyBuffer(device, indexBuffer.buffer, nil)

    vk.FreeMemory(device, vertexBuffer.memory, nil)
    vk.DestroyBuffer(device, vertexBuffer.buffer, nil)

    vk.DestroyPipeline(device, pipeline.handle, nil)
    vk.DestroyPipelineLayout(device, pipeline.layout, nil)

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




// ██████  ██████   █████  ██     ██ 
// ██   ██ ██   ██ ██   ██ ██     ██ 
// ██   ██ ██████  ███████ ██  █  ██ 
// ██   ██ ██   ██ ██   ██ ██ ███ ██ 
// ██████  ██   ██ ██   ██  ███ ███  


DrawFrameDR :: proc(using ctx: ^VulkanContext, vertices: []Vertex, indices: []u32)
{
    vk.WaitForFences(device, 1, &inFlight[curFrame], true, max(u64))

    imageIndex: u32

    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), imageAvailable[curFrame], {}, &imageIndex)
    if res == .ERROR_OUT_OF_DATE_KHR {
        RecreateSwapchainDR(ctx)
        return
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        LogError("Failed to acquire Swapchain Image!\n")
        os.exit(1)
    }
    vk.ResetFences(device, 1, &inFlight[curFrame])
    vk.ResetCommandBuffer(commandBuffers[curFrame], {})
    RecordCommandBufferDR(ctx, commandBuffers[curFrame], imageIndex)

    UpdateUniformBuffer(ctx, curFrame)

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

    TransitionImageDR(ctx, swapchain.images[imageIndex], .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR, mipLevels)

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
        RecreateSwapchainDR(ctx)
    } else if res != .SUCCESS {
        LogError("Failed to present Swapchain Image!\n")
        os.exit(1)
    }
    curFrame = (curFrame + 1) % MAX_FRAMES_IN_FLIGHT
}


// ███████ ██     ██  █████  ██████   ██████ ██   ██  █████  ██ ███    ██ 
// ██      ██     ██ ██   ██ ██   ██ ██      ██   ██ ██   ██ ██ ████   ██ 
// ███████ ██  █  ██ ███████ ██████  ██      ███████ ███████ ██ ██ ██  ██ 
//      ██ ██ ███ ██ ██   ██ ██      ██      ██   ██ ██   ██ ██ ██  ██ ██ 
// ███████  ███ ███  ██   ██ ██       ██████ ██   ██ ██   ██ ██ ██   ████ 


CreateSwapchainDR :: proc(using ctx: ^VulkanContext)
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

CleanupSwapchainDR :: proc(using ctx: ^VulkanContext)
{
    vk.DestroyImageView(device, colorImageView, nil)
    vk.DestroyImage(device, colorImage.image, nil)
    vk.FreeMemory(device, colorImage.memory, nil)
    vk.DestroyImageView(device, depthImageView, nil)
    vk.DestroyImage(device, depthImage.image, nil)
    vk.FreeMemory(device, depthImage.memory, nil)

    // for f in swapchain.framebuffers
    // {
    //     vk.DestroyFramebuffer(device, f, nil)
    // }
    for view in swapchain.imageViews
    {
        vk.DestroyImageView(device, view, nil)
    }
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

RecreateSwapchainDR :: proc(using ctx: ^VulkanContext)
{
    width, height: i32 = 0, 0
    width, height = glfw.GetFramebufferSize(window)
    for width == 0 || height == 0
    {
        glfw.WaitEvents()
        width, height = glfw.GetFramebufferSize(window)
    }
    vk.DeviceWaitIdle(device)

    mipLevels = 1

    CleanupSwapchainDR(ctx)

    QuerySwapchainDetails(ctx, physicalDevice)

    CreateSwapchainDR(ctx)

    CreateImageViews(ctx)
    if MSAA_ENABLED {
        CreateColorResources(ctx)
    }
    CreateDepthResources(ctx)
}


// ██████  ██ ██████  ███████ ██      ██ ███    ██ ███████ 
// ██   ██ ██ ██   ██ ██      ██      ██ ████   ██ ██      
// ██████  ██ ██████  █████   ██      ██ ██ ██  ██ █████   
// ██      ██ ██      ██      ██      ██ ██  ██ ██ ██      
// ██      ██ ██      ███████ ███████ ██ ██   ████ ███████ 


CreateGraphicsPipelineDR :: proc(using ctx: ^VulkanContext, vsName: string, fsName: string)
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
    rasterizer.frontFace = .COUNTER_CLOCKWISE
    rasterizer.depthBiasEnable = false
    rasterizer.depthBiasConstantFactor = 0.0
    rasterizer.depthBiasClamp = 0.0
    rasterizer.depthBiasSlopeFactor = 0.0

    multisampling: vk.PipelineMultisampleStateCreateInfo
    multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    multisampling.sampleShadingEnable = false
    if MSAA_ENABLED {
        multisampling.rasterizationSamples = {msaaSamples}
    } else {
        multisampling.rasterizationSamples = {._1}
    }
    multisampling.minSampleShading = 1.0
    multisampling.pSampleMask = nil
    multisampling.alphaToCoverageEnable = false
    multisampling.alphaToOneEnable = false

    depthStencil: vk.PipelineDepthStencilStateCreateInfo
    depthStencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
    depthStencil.depthTestEnable = true
    depthStencil.depthWriteEnable = true
    depthStencil.depthCompareOp = .LESS
    depthStencil.depthBoundsTestEnable = false
    depthStencil.stencilTestEnable = false

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
    pipelineLayoutInfo.setLayoutCount = 1
    pipelineLayoutInfo.pSetLayouts = &descriptorSetLayout
    pipelineLayoutInfo.pushConstantRangeCount = 0
    pipelineLayoutInfo.pPushConstantRanges = nil

    if res := vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &pipeline.layout); res != .SUCCESS {
        LogError("Failed to create Pipeline Layout!\n")
        os.exit(1)
    }

    pipelineRenderingInfo: vk.PipelineRenderingCreateInfo
    pipelineRenderingInfo.sType = .PIPELINE_RENDERING_CREATE_INFO
    pipelineRenderingInfo.pNext = nil
    pipelineRenderingInfo.colorAttachmentCount = 1
    pipelineRenderingInfo.pColorAttachmentFormats = &swapchain.format.format
    pipelineRenderingInfo.depthAttachmentFormat = FindDepthFormat(ctx)

    pipelineInfo: vk.GraphicsPipelineCreateInfo
    pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
    pipelineInfo.stageCount = 2
    pipelineInfo.pStages = &shaderStages[0]
    pipelineInfo.pVertexInputState = &vertexInput
    pipelineInfo.pInputAssemblyState = &inputAssembly
    pipelineInfo.pViewportState = &viewportState
    pipelineInfo.pRasterizationState = &rasterizer
    pipelineInfo.pMultisampleState = &multisampling
    pipelineInfo.pDepthStencilState = &depthStencil
    pipelineInfo.pColorBlendState = &colorBlending
    pipelineInfo.pDynamicState = &dynamicState
    pipelineInfo.layout = pipeline.layout
    pipelineInfo.renderPass = {}
    pipelineInfo.pNext = &pipelineRenderingInfo
    pipelineInfo.subpass = 0
    pipelineInfo.basePipelineHandle = vk.Pipeline{}
    pipelineInfo.basePipelineIndex = -1

    if res := vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline.handle); res != .SUCCESS {
        LogError("Failed to create Graphics Pipeline!\n")
        os.exit(1)
    }
}


// ██████  ██████  ███    ███ ███    ███  █████  ███    ██ ██████  ███████ 
// ██      ██    ██ ████  ████ ████  ████ ██   ██ ████   ██ ██   ██ ██      
// ██      ██    ██ ██ ████ ██ ██ ████ ██ ███████ ██ ██  ██ ██   ██ ███████ 
// ██      ██    ██ ██  ██  ██ ██  ██  ██ ██   ██ ██  ██ ██ ██   ██      ██ 
//  ██████  ██████  ██      ██ ██      ██ ██   ██ ██   ████ ██████  ███████ 


RecordCommandBufferDR :: proc(using ctx: ^VulkanContext, buffer: vk.CommandBuffer, imageIndex: u32)
{
    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.flags = {.ONE_TIME_SUBMIT}
    beginInfo.pInheritanceInfo = nil
    
    if res := vk.BeginCommandBuffer(buffer, &beginInfo); res != .SUCCESS {
        LogError("Failed to begin recording Command Buffer!\n")
        os.exit(1)
    }

    TransitionImageDR(ctx, swapchain.images[imageIndex], .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL, mipLevels)

    clearColors: [2]vk.ClearValue
    clearColors[0].color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
    clearColors[1].depthStencil = {1.0, 0.0}

    colorAttachmentInfo: vk.RenderingAttachmentInfo
    colorAttachmentInfo.sType = .RENDERING_ATTACHMENT_INFO
    colorAttachmentInfo.imageView = swapchain.imageViews[imageIndex]
    colorAttachmentInfo.imageLayout = .COLOR_ATTACHMENT_OPTIMAL
    colorAttachmentInfo.loadOp = .CLEAR
    colorAttachmentInfo.storeOp = .STORE
    colorAttachmentInfo.clearValue = clearColors[0]

    depthAttachment: vk.RenderingAttachmentInfo
    depthAttachment.sType = .RENDERING_ATTACHMENT_INFO
    depthAttachment.imageView = depthImageView
    depthAttachment.imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    depthAttachment.loadOp = .CLEAR
    depthAttachment.storeOp = .DONT_CARE
    depthAttachment.clearValue = clearColors[1]

    renderInfo: vk.RenderingInfo
    renderInfo.sType = .RENDERING_INFO
    renderInfo.renderArea = vk.Rect2D{vk.Offset2D{}, swapchain.extent}
    renderInfo.layerCount = 1
    renderInfo.colorAttachmentCount = 1
    renderInfo.pColorAttachments = &colorAttachmentInfo
    renderInfo.pDepthAttachment = &depthAttachment

    vk.CmdBeginRendering(buffer, &renderInfo)

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline.handle)

    vertexBuffers := [?]vk.Buffer{vertexBuffer.buffer}
    offsets := [?]vk.DeviceSize{0}
    vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
    vk.CmdBindIndexBuffer(buffer, indexBuffer.buffer, 0, .UINT32)

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

    vk.CmdBindDescriptorSets(buffer, .GRAPHICS, pipeline.layout, 0, 1, &descriptorSets[curFrame], 0, nil)

    vk.CmdDrawIndexed(buffer, cast(u32)indexBuffer.length, 1, 0, 0, 0)

    vk.CmdEndRendering(buffer)

    if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
        LogError("Failed to record Command Buffer!\n")
        os.exit(1)
    }    
}

TransitionImageDR :: proc(using ctx: ^VulkanContext, image: vk.Image, oldLayout, newLayout: vk.ImageLayout, mips: u32)
{
    cmdBuffer := BeginSingleTimeCommands(ctx)

    barrier: vk.ImageMemoryBarrier
    barrier.sType = .IMAGE_MEMORY_BARRIER
    barrier.oldLayout = oldLayout
    barrier.newLayout = newLayout
    barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.image = image
    barrier.subresourceRange.aspectMask = {.COLOR}
    barrier.subresourceRange.baseMipLevel = 0
    barrier.subresourceRange.levelCount = mips
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1

    sourceStage: vk.PipelineStageFlags
    destinationStage: vk.PipelineStageFlags

    if (oldLayout == .UNDEFINED && newLayout == .COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.COLOR_ATTACHMENT_WRITE}

        sourceStage = {.TOP_OF_PIPE}
        destinationStage = {.COLOR_ATTACHMENT_OUTPUT}
    } else if (oldLayout == .COLOR_ATTACHMENT_OPTIMAL && newLayout == .PRESENT_SRC_KHR) {
        barrier.srcAccessMask = {.COLOR_ATTACHMENT_WRITE}
        barrier.dstAccessMask = {}

        sourceStage = {.COLOR_ATTACHMENT_OUTPUT}
        destinationStage = {.BOTTOM_OF_PIPE}
    } else {
        LogError("Unsupported Layout Transition!")
        os.exit(1)
    }

    vk.CmdPipelineBarrier(cmdBuffer, sourceStage, destinationStage, {}, 0, nil, 0, nil, 1, &barrier)

    EndSingleTimeCommands(ctx, &cmdBuffer)
}

//
// -->
//

CreateInstanceDR :: proc(using ctx: ^VulkanContext)
{
    appInfo: vk.ApplicationInfo
    appInfo.sType = .APPLICATION_INFO
    appInfo.pApplicationName = "Comfytree"
    appInfo.applicationVersion = vk.MAKE_VERSION(0, 1, 1)
    appInfo.pEngineName = "Comfytree"
    appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
    appInfo.apiVersion = vk.API_VERSION_1_3

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

CreateLogicalDeviceDR :: proc(using ctx: ^VulkanContext)
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
    enabledFeatures.samplerAnisotropy = true

    enabledFeatures12: vk.PhysicalDeviceVulkan12Features
    enabledFeatures12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
    enabledFeatures12.bufferDeviceAddress = true
    enabledFeatures12.descriptorIndexing = true

    enabledFeatures13: vk.PhysicalDeviceVulkan13Features
    enabledFeatures13.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES
    enabledFeatures13.dynamicRendering = true
    enabledFeatures13.synchronization2 = true
    enabledFeatures13.pNext = &enabledFeatures12

    deviceCreateInfo: vk.DeviceCreateInfo
    deviceCreateInfo.sType = .DEVICE_CREATE_INFO
    deviceCreateInfo.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS))
    deviceCreateInfo.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
    deviceCreateInfo.queueCreateInfoCount = u32(len(queueCreateInfos))
    deviceCreateInfo.pQueueCreateInfos = raw_data(queueCreateInfos)
    deviceCreateInfo.pEnabledFeatures = &enabledFeatures
    deviceCreateInfo.enabledLayerCount = 0
    deviceCreateInfo.pNext = &enabledFeatures13

    if res := vk.CreateDevice(physicalDevice, &deviceCreateInfo, nil, &device); res != .SUCCESS {
        LogError("Failed to create Logical Device!")
        os.exit(1)
    }
}

ReloadShaderModulesDR :: proc(using ctx: ^VulkanContext)
{
    //TODO: Query for potential shader file changes + maybe create pipeline update in background and then swap out?
    LogInfo("Reloading Shaders...")
    vk.DeviceWaitIdle(device)
    vk.DestroyPipeline(device, pipeline.handle, nil)
    CreateGraphicsPipelineDR(ctx, "vert", "frag")
    vk.FreeCommandBuffers(device, commandPool, len(commandBuffers), raw_data(commandBuffers[:]))
    CreateCommandBuffers(ctx)
}