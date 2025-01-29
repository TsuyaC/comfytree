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
        format = .R32G32B32_SFLOAT,
        offset = cast(u32)offset_of(Vertex, pos),
    },
    {
        binding = 0,
        location = 1,
        format = .R32G32B32_SFLOAT,
        offset = cast(u32)offset_of(Vertex, color),
    },
    {
        binding = 0,
        location = 2,
        format = .R32G32_SFLOAT,
        offset = cast(u32)offset_of(Vertex, texCoord)
    },
}

UniformBufferObject :: struct {
    model:  glm.mat4,
    view:   glm.mat4,
    proj:   glm.mat4,
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
    uniformBuffers:         []Buffer,

    imageAvailable:         [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinished:         [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlight:               [MAX_FRAMES_IN_FLIGHT]vk.Fence,

    curFrame:               u32,
    framebufferResized:     bool,

    descriptorSetLayout:    vk.DescriptorSetLayout,
    descriptorPool:         vk.DescriptorPool,
    descriptorSets:         []vk.DescriptorSet,

    textureImage:           TexImage,
    textureImageView:       vk.ImageView,
    textureSampler:         vk.Sampler,

    depthImage:             TexImage,
    depthImageView:         vk.ImageView
}


Vertex :: struct {
    pos:        glm.vec3,
    color:      glm.vec3,
    texCoord:   glm.vec2,
}

@(private="file")
Buffer :: struct {
    buffer:     vk.Buffer,
    memory:     vk.DeviceMemory,
    length:     int,
    size:       vk.DeviceSize
}

@(private="file")
TexImage :: struct {
    image:  vk.Image,
    memory: vk.DeviceMemory,
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

    // LogInfo("Queue Indices:")
    for q, f in queueIndices do fmt.printf(" %v: %d\n", f, q)

    CreateLogicalDevice(ctx)

    for &q, f in &queues
    {
        vk.GetDeviceQueue(device, u32(queueIndices[f]), 0, &q)
    }

    CreateSwapchain(ctx)
    CreateImageViews(ctx)
    CreateDescriptorSetLayout(ctx)
    CreateGraphicsPipeline(ctx, "vert.spv", "frag.spv")
    CreateCommandPool(ctx)
    CreateDepthResources(ctx)
    CreateFramebuffers(ctx)
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

CleanupVulkan :: proc(using ctx: ^VulkanContext)
{
    vk.DeviceWaitIdle(device)
    CleanupSwapchain(ctx)

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


// ██ ███    ███  █████   ██████  ███████ 
// ██ ████  ████ ██   ██ ██       ██      
// ██ ██ ████ ██ ███████ ██   ███ █████   
// ██ ██  ██  ██ ██   ██ ██    ██ ██      
// ██ ██      ██ ██   ██  ██████  ███████


CreateTextureImage :: proc(using ctx: ^VulkanContext)
{
    texWidth, texHeight, texChannels: i32
    pixels := stbi.load("./textures/texture.jpg", &texWidth, &texHeight, &texChannels, 4)
    imageSize := vk.DeviceSize(texWidth * texHeight * 4)

    if pixels == nil {
        LogError("Failed to load Texture Image!")
    }

    stagingBuffer: Buffer
    CreateBuffer(ctx, int(imageSize), 1, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuffer)

    data: rawptr
    vk.MapMemory(device, stagingBuffer.memory, 0, imageSize, {}, &data)
    mem.copy(data, pixels, int(imageSize))
    vk.UnmapMemory(device, stagingBuffer.memory)

    stbi.image_free(pixels)

    CreateImage(ctx, u32(texWidth), u32(texHeight), vk.Format.R8G8B8A8_SRGB, vk.ImageTiling.OPTIMAL, {vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.SAMPLED}, {vk.MemoryPropertyFlag.DEVICE_LOCAL}, &textureImage)

    TransitionImageLayout(ctx, textureImage.image, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
    CopyBufferToImage(ctx, stagingBuffer.buffer, textureImage.image, u32(texWidth), u32(texHeight))
    TransitionImageLayout(ctx, textureImage.image, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL)

    vk.DestroyBuffer(device, stagingBuffer.buffer, nil)
    vk.FreeMemory(device, stagingBuffer.memory, nil)
}

CreateImage :: proc(using ctx: ^VulkanContext, width, height: u32, format: vk.Format, tiling: vk.ImageTiling, usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, image: ^TexImage)
{
    imageInfo: vk.ImageCreateInfo
    imageInfo.sType = .IMAGE_CREATE_INFO
    imageInfo.imageType = .D2
    imageInfo.extent.width = width
    imageInfo.extent.height = height
    imageInfo.extent.depth = 1
    imageInfo.mipLevels = 1
    imageInfo.arrayLayers = 1
    imageInfo.format = format
    imageInfo.tiling = tiling
    imageInfo.initialLayout = .UNDEFINED
    imageInfo.usage = usage
    imageInfo.samples = {._1}
    imageInfo.sharingMode = .EXCLUSIVE

    if res := vk.CreateImage(device, &imageInfo, nil, &image.image); res != .SUCCESS {
        LogError("Failed to create Image!")
        os.exit(1)
    }

    memReqs: vk.MemoryRequirements
    vk.GetImageMemoryRequirements(device, image.image, &memReqs)

    allocInfo: vk.MemoryAllocateInfo
    allocInfo.sType = .MEMORY_ALLOCATE_INFO
    allocInfo.allocationSize = memReqs.size
    allocInfo.memoryTypeIndex = FindMemoryType(ctx, memReqs.memoryTypeBits, properties)

    if res := vk.AllocateMemory(device, &allocInfo, nil, &image.memory); res != .SUCCESS {
        LogError("Failed to allocate Image Memory!")
        os.exit(1)
    }

    vk.BindImageMemory(device, image.image, image.memory, 0)
}

TransitionImageLayout :: proc(using ctx: ^VulkanContext, image: vk.Image, format: vk.Format, oldLayout, newLayout: vk.ImageLayout)
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
    barrier.subresourceRange.levelCount = 1
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1

    sourceStage: vk.PipelineStageFlags
    destinationStage: vk.PipelineStageFlags

    if (oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_WRITE}

        sourceStage = {.TOP_OF_PIPE}
        destinationStage = {.TRANSFER}
    } else if (oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = {.TRANSFER_WRITE}
        barrier.dstAccessMask = {.SHADER_READ}

        sourceStage = {.TRANSFER}
        destinationStage = {.FRAGMENT_SHADER}
    } else {
        LogError("Unsupported Layout Transition!")
        os.exit(1)
    }

    vk.CmdPipelineBarrier(cmdBuffer, sourceStage, destinationStage, {}, 0, nil, 0, nil, 1, &barrier)

    EndSingleTimeCommands(ctx, &cmdBuffer)
}

CopyBufferToImage :: proc(using ctx: ^VulkanContext, buffer: vk.Buffer, image: vk.Image, width, height: u32)
{
    cmdBuffer := BeginSingleTimeCommands(ctx)

    region: vk.BufferImageCopy
    region.bufferOffset = 0
    region.bufferRowLength = 0
    region.bufferImageHeight = 0

    region.imageSubresource.aspectMask = {.COLOR}
    region.imageSubresource.mipLevel = 0
    region.imageSubresource.baseArrayLayer = 0
    region.imageSubresource.layerCount = 1

    region.imageOffset = {0, 0, 0}
    region.imageExtent = {width, height, 1}

    vk.CmdCopyBufferToImage(cmdBuffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)

    EndSingleTimeCommands(ctx, &cmdBuffer)
}

CreateImageView :: proc(using ctx: ^VulkanContext, image: vk.Image, format: vk.Format, aspectFlags: vk.ImageAspectFlags) -> vk.ImageView
{
    viewInfo: vk.ImageViewCreateInfo
    viewInfo.sType = .IMAGE_VIEW_CREATE_INFO
    viewInfo.image = image
    viewInfo.viewType = .D2
    viewInfo.format = format
    viewInfo.subresourceRange.aspectMask = aspectFlags
    viewInfo.subresourceRange.baseMipLevel = 0
    viewInfo.subresourceRange.levelCount = 1
    viewInfo.subresourceRange.baseArrayLayer = 0
    viewInfo.subresourceRange.layerCount = 1

    imageView: vk.ImageView
    if res := vk.CreateImageView(device, &viewInfo, nil, &imageView); res != .SUCCESS {
        LogError("Failed to create Texture Image View!")
        os.exit(1)
    }

    return imageView
}

CreateTextureImageView :: proc(using ctx: ^VulkanContext)
{
    textureImageView = CreateImageView(ctx, textureImage.image, .R8G8B8A8_SRGB, {.COLOR})
}

CreateImageViews :: proc(using ctx: ^VulkanContext)
{
    using ctx.swapchain

    imageViews = make([]vk.ImageView, len(images))

    for _, i in images
    {
        imageViews[i] = CreateImageView(ctx, images[i], format.format, {.COLOR})
    }
}

CreateTextureSampler :: proc(using ctx: ^VulkanContext)
{
    samplerInfo: vk.SamplerCreateInfo
    samplerInfo.sType = .SAMPLER_CREATE_INFO
    samplerInfo.magFilter = .LINEAR
    samplerInfo.minFilter = .LINEAR
    samplerInfo.addressModeU = .REPEAT
    samplerInfo.addressModeV = .REPEAT
    samplerInfo.addressModeW = .REPEAT
    samplerInfo.anisotropyEnable = true
    samplerInfo.maxAnisotropy = physicalDeviceProps.limits.maxSamplerAnisotropy
    samplerInfo.borderColor = .INT_OPAQUE_BLACK
    samplerInfo.unnormalizedCoordinates = false
    samplerInfo.compareEnable = false
    samplerInfo.compareOp = .ALWAYS
    samplerInfo.mipmapMode = .LINEAR
    samplerInfo.mipLodBias = 0.0
    samplerInfo.minLod = 0.0
    samplerInfo.maxLod = 0.0

    if res := vk.CreateSampler(device, &samplerInfo, nil, &textureSampler); res != .SUCCESS {
        LogError("Failed to create Texture Sampler!")
        os.exit(1)
    }
}


// ██████  ███████ ██████  ████████ ██   ██ 
// ██   ██ ██      ██   ██    ██    ██   ██ 
// ██   ██ █████   ██████     ██    ███████ 
// ██   ██ ██      ██         ██    ██   ██ 
// ██████  ███████ ██         ██    ██   ██ 


CreateDepthResources :: proc(using ctx: ^VulkanContext)
{
    depthFormat := FindDepthFormat(ctx)

    CreateImage(ctx, swapchain.extent.width, swapchain.extent.height, depthFormat, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &depthImage)
    depthImageView = CreateImageView(ctx, depthImage.image, depthFormat, {.DEPTH})
}

FindDepthFormat :: proc(using ctx: ^VulkanContext) -> vk.Format
{
    return FindSupportedFormat(ctx, &[]vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

FindSupportedFormat :: proc(using ctx: ^VulkanContext, candidates: ^[]vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format
{
    res: vk.Format

    for format in candidates
    {
        props: vk.FormatProperties
        vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &props)

        if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
            res = format
            return res
        } else if tiling == .OPTIMAL && (props.linearTilingFeatures & features) == features {
            res = format
            return res
        }
    }

    if res == nil {
        LogWarning("Failed to find a supported Format. Defaulting to D32_SFLOAT")
        return .D32_SFLOAT
    }

    return res
}

HasStencilComponent :: proc(format: vk.Format) -> bool 
{
    return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}


// ██████  ██ ██████  ███████ ██      ██ ███    ██ ███████ 
// ██   ██ ██ ██   ██ ██      ██      ██ ████   ██ ██      
// ██████  ██ ██████  █████   ██      ██ ██ ██  ██ █████   
// ██      ██ ██      ██      ██      ██ ██  ██ ██ ██      
// ██      ██ ██      ███████ ███████ ██ ██   ████ ███████ 


CreateGraphicsPipeline :: proc(using ctx: ^VulkanContext, vsName: string, fsName: string)
{
    // vsCode := CompileShader(vsName, .VertexShader)
    // fsCode := CompileShader(fsName, .FragmentShader)
    vsCode,_ := os.read_entire_file(fmt.tprintf("./shaders/%s", vsName))
    fsCode,_ := os.read_entire_file(fmt.tprintf("./shaders/%s", fsName))

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
    multisampling.rasterizationSamples = {._1}
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
    pipelineInfo.pDepthStencilState = &depthStencil
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

    depthAttachment: vk.AttachmentDescription
    depthAttachment.format = FindDepthFormat(ctx)
    depthAttachment.samples = {._1}
    depthAttachment.loadOp = .CLEAR
    depthAttachment.storeOp = .DONT_CARE
    depthAttachment.stencilLoadOp = .DONT_CARE
    depthAttachment.stencilStoreOp = .DONT_CARE
    depthAttachment.initialLayout = .UNDEFINED
    depthAttachment.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

    colorAttachmentRef: vk.AttachmentReference
    colorAttachmentRef.attachment = 0
    colorAttachmentRef.layout = .COLOR_ATTACHMENT_OPTIMAL

    depthAttachmentRef: vk.AttachmentReference
    depthAttachmentRef.attachment = 1
    depthAttachmentRef.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

    attachments := []vk.AttachmentDescription{colorAttachment, depthAttachment}

    subpass: vk.SubpassDescription
    subpass.pipelineBindPoint = .GRAPHICS
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = &colorAttachmentRef
    subpass.pDepthStencilAttachment = &depthAttachmentRef

    dependency: vk.SubpassDependency
    dependency.srcSubpass = vk.SUBPASS_EXTERNAL
    dependency.dstSubpass = 0
    dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
    dependency.srcAccessMask = {}
    dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
    dependency.dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE}

    renderPassInfo: vk.RenderPassCreateInfo
    renderPassInfo.sType = .RENDER_PASS_CREATE_INFO
    renderPassInfo.attachmentCount = u32(len(attachments))
    renderPassInfo.pAttachments = raw_data(attachments[:])
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

    clearColors: [2]vk.ClearValue
    clearColors[0].color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
    clearColors[1].depthStencil = {1.0, 0.0}
    renderPassInfo.clearValueCount = u32(len(clearColors))
    renderPassInfo.pClearValues = raw_data(clearColors[:])

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

    vk.CmdBindDescriptorSets(buffer, .GRAPHICS, pipeline.layout, 0, 1, &descriptorSets[curFrame], 0, nil)

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
    cmdBuffer := BeginSingleTimeCommands(ctx)

    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }
    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)

    EndSingleTimeCommands(ctx, &cmdBuffer)
}

BeginSingleTimeCommands :: proc(using ctx: ^VulkanContext) -> vk.CommandBuffer
{
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.level = .PRIMARY
    allocInfo.commandPool = commandPool
    allocInfo.commandBufferCount = 1

    cmdBuffer: vk.CommandBuffer
    vk.AllocateCommandBuffers(device, &allocInfo, &cmdBuffer)

    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.flags = {.ONE_TIME_SUBMIT}

    vk.BeginCommandBuffer(cmdBuffer, &beginInfo)

    return cmdBuffer
}

EndSingleTimeCommands :: proc(using ctx: ^VulkanContext, commandBuffer: ^vk.CommandBuffer)
{
    vk.EndCommandBuffer(commandBuffer^)

    submitInfo: vk.SubmitInfo
    submitInfo.sType = .SUBMIT_INFO
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = commandBuffer

    vk.QueueSubmit(queues[.Graphics], 1, &submitInfo, {})
    vk.QueueWaitIdle(queues[.Graphics])

    vk.FreeCommandBuffers(device, commandPool, 1, commandBuffer)
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

CreateUniformBuffers :: proc(using ctx: ^VulkanContext)
{
    uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    
    for &buf, i in uniformBuffers
    {
        buf.length = 1
        buf.size = size_of(UniformBufferObject)

        CreateBuffer(ctx, size_of(UniformBufferObject), buf.length, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &buf)

        data: rawptr
        vk.MapMemory(device, buf.memory, 0, buf.size, {}, &data)
        mem.copy(data, &buf.buffer, size_of(UniformBufferObject))
        vk.UnmapMemory(device, buf.memory)
    }
}

UpdateUniformBuffer :: proc(using ctx: ^VulkanContext, currentImage: u32)
{
    @(static)startTime: f64 = 0

    @(static) i := 0
    if i == 0 {
        startTime = glfw.GetTime()
        i += 1
    }

    currentTime := glfw.GetTime()
    time := currentTime - startTime

    ubo: UniformBufferObject
    ubo.model = glm.mat4(1.0) * glm.mat4Rotate({0.0, 0.0, 1.0}, f32(time) * m.to_radians_f32(90.0))
    ubo.view = glm.mat4LookAt({2.0, 2.0, 2.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 1.0})
    ubo.proj = glm.mat4Perspective(45, f32(swapchain.extent.width) / f32(swapchain.extent.height), 0.1, 10.0)
    ubo.proj[1][1] *= -1

    data: rawptr
    vk.MapMemory(device, uniformBuffers[currentImage].memory, 0, size_of(UniformBufferObject), {}, &data)
    mem.copy(data, &ubo, size_of(ubo))
    vk.UnmapMemory(device, uniformBuffers[curFrame].memory)
}

CreateDescriptorPool :: proc(using ctx: ^VulkanContext)
{
    poolSizes: [dynamic]vk.DescriptorPoolSize
    resize(&poolSizes, 2)
    poolSizes[0].type = .UNIFORM_BUFFER
    poolSizes[0].descriptorCount = cast(u32)MAX_FRAMES_IN_FLIGHT
    poolSizes[1].type = .COMBINED_IMAGE_SAMPLER
    poolSizes[1].descriptorCount = cast(u32)MAX_FRAMES_IN_FLIGHT

    poolInfo: vk.DescriptorPoolCreateInfo
    poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
    poolInfo.poolSizeCount = u32(len(poolSizes))
    poolInfo.pPoolSizes = raw_data(poolSizes)
    poolInfo.maxSets = cast(u32)MAX_FRAMES_IN_FLIGHT

    if res := vk.CreateDescriptorPool(device, &poolInfo, nil, &descriptorPool); res != .SUCCESS {
        LogError("Failed to create Descriptor Pool!")
        os.exit(1)
    }
}

CreateDescriptorSets :: proc(using ctx: ^VulkanContext)
{
    layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    defer delete(layouts)
    for &l in layouts
    {
        l = descriptorSetLayout
    }

    allocInfo: vk.DescriptorSetAllocateInfo
    allocInfo.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
    allocInfo.descriptorPool = descriptorPool
    allocInfo.descriptorSetCount = cast(u32)MAX_FRAMES_IN_FLIGHT
    allocInfo.pSetLayouts = &layouts[0]

    descriptorSets = make([]vk.DescriptorSet, MAX_FRAMES_IN_FLIGHT)
    if res := vk.AllocateDescriptorSets(device, &allocInfo, &descriptorSets[0]); res != .SUCCESS {
        LogError("Failed to allocate Descriptor Sets!")
        os.exit(1)
    }

    for i in 0..<MAX_FRAMES_IN_FLIGHT
    {
        bufferInfo: vk.DescriptorBufferInfo
        bufferInfo.buffer = uniformBuffers[i].buffer
        bufferInfo.offset = 0
        bufferInfo.range = size_of(UniformBufferObject)

        imageInfo: vk.DescriptorImageInfo
        imageInfo.imageLayout = .READ_ONLY_OPTIMAL
        imageInfo.imageView = textureImageView
        imageInfo.sampler = textureSampler

        descriptorWrites: [dynamic]vk.WriteDescriptorSet
        resize(&descriptorWrites, 2)
        // Uniform Buffer
        descriptorWrites[0].sType = .WRITE_DESCRIPTOR_SET
        descriptorWrites[0].dstSet = descriptorSets[i]
        descriptorWrites[0].dstBinding = 0
        descriptorWrites[0].dstArrayElement = 0
        descriptorWrites[0].descriptorType = .UNIFORM_BUFFER
        descriptorWrites[0].descriptorCount = 1
        descriptorWrites[0].pBufferInfo = &bufferInfo
        // Sampler
        descriptorWrites[1].sType = .WRITE_DESCRIPTOR_SET
        descriptorWrites[1].dstSet = descriptorSets[i]
        descriptorWrites[1].dstBinding = 1
        descriptorWrites[1].dstArrayElement = 0
        descriptorWrites[1].descriptorType = .COMBINED_IMAGE_SAMPLER
        descriptorWrites[1].descriptorCount = 1
        descriptorWrites[1].pImageInfo = &imageInfo

        vk.UpdateDescriptorSets(device, u32(len(descriptorWrites)), raw_data(descriptorWrites), 0, nil)
    }
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
    enabledFeatures.samplerAnisotropy = true

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

CreateDescriptorSetLayout :: proc(using ctx: ^VulkanContext)
{
    uboLayoutBinding: vk.DescriptorSetLayoutBinding
    uboLayoutBinding.binding = 0
    uboLayoutBinding.descriptorType = .UNIFORM_BUFFER
    uboLayoutBinding.descriptorCount = 1
    uboLayoutBinding.stageFlags = {.VERTEX}

    samplerLayoutBinding: vk.DescriptorSetLayoutBinding
    samplerLayoutBinding.binding = 1
    samplerLayoutBinding.descriptorType = .COMBINED_IMAGE_SAMPLER
    samplerLayoutBinding.descriptorCount = 1
    samplerLayoutBinding.stageFlags = {.FRAGMENT}

    bindings := []vk.DescriptorSetLayoutBinding{uboLayoutBinding, samplerLayoutBinding}

    layoutInfo: vk.DescriptorSetLayoutCreateInfo
    layoutInfo.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layoutInfo.bindingCount = u32(len(bindings))
    layoutInfo.pBindings = raw_data(bindings)

    if res := vk.CreateDescriptorSetLayout(device, &layoutInfo, nil, &descriptorSetLayout); res != .SUCCESS {
        LogError("Failed to create Descriptor Set Layout!")
        os.exit(1)
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

    // Include if using oldSwapchain!
    // if (swapchain.format != oldSwapchain.format) {
    //     vk.DestroyRenderPass(device, pipeline.renderPass, nil)
    //     CreateRenderPass(ctx)
    // }

    CreateImageViews(ctx)
    CreateDepthResources(ctx)
    CreateFramebuffers(ctx)
}

CleanupSwapchain :: proc(using ctx: ^VulkanContext)
{
    vk.DestroyImageView(device, depthImageView, nil)
    vk.DestroyImage(device, depthImage.image, nil)
    vk.FreeMemory(device, depthImage.memory, nil)

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
        attachments := [?]vk.ImageView{v, depthImageView}

        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = pipeline.renderPass
        framebufferInfo.attachmentCount = u32(len(attachments))
        framebufferInfo.pAttachments = raw_data(attachments[:])
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
        if !features.samplerAnisotropy do return 0
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
        if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
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