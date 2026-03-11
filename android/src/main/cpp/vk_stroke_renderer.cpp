// vk_stroke_renderer.cpp — Pure C++ Vulkan stroke renderer implementation
// Triangle strip tessellation + round caps, rendered via Vulkan swapchain
// into Flutter's ANativeWindow (TextureRegistry SurfaceTexture).

#include "vk_stroke_renderer.h"
#include "vk_shaders.h"
#include <algorithm>
#include <array>
#include <cstring>

// ═══════════════════════════════════════════════════════════════════
// DESTRUCTOR
// ═══════════════════════════════════════════════════════════════════

VkStrokeRenderer::~VkStrokeRenderer() { destroy(); }

// ═══════════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::init(ANativeWindow *window, int width, int height) {
  if (initialized_)
    destroy();
  window_ = window;
  width_ = width;
  height_ = height;

  // Identity transform
  memset(transform_, 0, sizeof(transform_));
  transform_[0] = transform_[5] = transform_[10] = transform_[15] = 1.0f;

  if (!createInstance())
    return false;
  if (!pickPhysicalDevice())
    return false;
  if (!createDevice())
    return false;
  if (!createSurface(window))
    return false;
  if (!createSwapchain())
    return false;
  if (!createMsaaResources())
    return false;
  if (!createRenderPass())
    return false;
  if (!createPipeline())
    return false;
  if (!createFramebuffers())
    return false;
  if (!createCommandPool())
    return false;
  if (!createVertexBuffer())
    return false;
  if (!createSyncObjects())
    return false;

  initialized_ = true;
  LOGI("VkStrokeRenderer initialized: %dx%d", width, height);
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// VULKAN INSTANCE
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createInstance() {
  VkApplicationInfo appInfo{};
  appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  appInfo.pApplicationName = "FlueraStroke";
  appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
  appInfo.pEngineName = "FluEra";
  appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
  appInfo.apiVersion = VK_API_VERSION_1_1;

  const char *extensions[] = {
      VK_KHR_SURFACE_EXTENSION_NAME,
      VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
  };

  VkInstanceCreateInfo ci{};
  ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  ci.pApplicationInfo = &appInfo;
  ci.enabledExtensionCount = 2;
  ci.ppEnabledExtensionNames = extensions;

  VK_CHECK(vkCreateInstance(&ci, nullptr, &instance_));
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// PHYSICAL DEVICE
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::pickPhysicalDevice() {
  uint32_t count = 0;
  vkEnumeratePhysicalDevices(instance_, &count, nullptr);
  if (count == 0) {
    LOGE("No Vulkan physical devices found");
    return false;
  }
  std::vector<VkPhysicalDevice> devices(count);
  vkEnumeratePhysicalDevices(instance_, &count, devices.data());
  physDevice_ = devices[0]; // Pick first device (usually the GPU)

  vkGetPhysicalDeviceProperties(physDevice_, &deviceProps_);
  LOGI("Vulkan device: %s (API %d.%d.%d)", deviceProps_.deviceName,
       VK_VERSION_MAJOR(deviceProps_.apiVersion),
       VK_VERSION_MINOR(deviceProps_.apiVersion),
       VK_VERSION_PATCH(deviceProps_.apiVersion));
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// LOGICAL DEVICE + QUEUE
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createDevice() {
  uint32_t qfCount = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &qfCount, nullptr);
  std::vector<VkQueueFamilyProperties> qfProps(qfCount);
  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &qfCount,
                                           qfProps.data());

  queueFamily_ = UINT32_MAX;
  for (uint32_t i = 0; i < qfCount; i++) {
    if (qfProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
      queueFamily_ = i;
      break;
    }
  }
  if (queueFamily_ == UINT32_MAX) {
    LOGE("No graphics queue family");
    return false;
  }

  float priority = 1.0f;
  VkDeviceQueueCreateInfo qci{};
  qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  qci.queueFamilyIndex = queueFamily_;
  qci.queueCount = 1;
  qci.pQueuePriorities = &priority;

  const char *devExts[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};

  VkDeviceCreateInfo dci{};
  dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  dci.queueCreateInfoCount = 1;
  dci.pQueueCreateInfos = &qci;
  dci.enabledExtensionCount = 1;
  dci.ppEnabledExtensionNames = devExts;

  VK_CHECK(vkCreateDevice(physDevice_, &dci, nullptr, &device_));
  vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// SURFACE (from ANativeWindow)
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createSurface(ANativeWindow *window) {
  VkAndroidSurfaceCreateInfoKHR sci{};
  sci.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
  sci.window = window;
  VK_CHECK(vkCreateAndroidSurfaceKHR(instance_, &sci, nullptr, &surface_));
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// SWAPCHAIN
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createSwapchain() {
  VkSurfaceCapabilitiesKHR caps;
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physDevice_, surface_, &caps);

  // Pick format
  uint32_t fmtCount = 0;
  vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice_, surface_, &fmtCount,
                                       nullptr);
  std::vector<VkSurfaceFormatKHR> fmts(fmtCount);
  vkGetPhysicalDeviceSurfaceFormatsKHR(physDevice_, surface_, &fmtCount,
                                       fmts.data());

  swapFormat_ = fmts[0].format;
  VkColorSpaceKHR colorSpace = fmts[0].colorSpace;
  for (auto &f : fmts) {
    if (f.format == VK_FORMAT_R8G8B8A8_UNORM) {
      swapFormat_ = f.format;
      colorSpace = f.colorSpace;
      break;
    }
  }

  swapExtent_ = caps.currentExtent;
  if (swapExtent_.width == UINT32_MAX) {
    swapExtent_.width = static_cast<uint32_t>(width_);
    swapExtent_.height = static_cast<uint32_t>(height_);
  }

  uint32_t imageCount = caps.minImageCount + 1;
  if (caps.maxImageCount > 0 && imageCount > caps.maxImageCount)
    imageCount = caps.maxImageCount;

  VkSwapchainCreateInfoKHR sci{};
  sci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  sci.surface = surface_;
  sci.minImageCount = imageCount;
  sci.imageFormat = swapFormat_;
  sci.imageColorSpace = colorSpace;
  sci.imageExtent = swapExtent_;
  sci.imageArrayLayers = 1;
  sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  sci.preTransform = caps.currentTransform;
  sci.compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
  // Prefer MAILBOX (lowest latency), fallback to FIFO
  sci.presentMode = VK_PRESENT_MODE_MAILBOX_KHR;
  sci.clipped = VK_TRUE;

  VK_CHECK(vkCreateSwapchainKHR(device_, &sci, nullptr, &swapchain_));

  uint32_t imgCount = 0;
  vkGetSwapchainImagesKHR(device_, swapchain_, &imgCount, nullptr);
  swapImages_.resize(imgCount);
  vkGetSwapchainImagesKHR(device_, swapchain_, &imgCount, swapImages_.data());

  // Create image views
  swapViews_.resize(imgCount);
  for (uint32_t i = 0; i < imgCount; i++) {
    VkImageViewCreateInfo vci{};
    vci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    vci.image = swapImages_[i];
    vci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vci.format = swapFormat_;
    vci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    vci.subresourceRange.levelCount = 1;
    vci.subresourceRange.layerCount = 1;
    VK_CHECK(vkCreateImageView(device_, &vci, nullptr, &swapViews_[i]));
  }

  return true;
}

// ═══════════════════════════════════════════════════════════════════
// RENDER PASS
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createRenderPass() {
  // Attachment 0: MSAA color (drawn to, not stored)
  VkAttachmentDescription msaaAtt{};
  msaaAtt.format = swapFormat_;
  msaaAtt.samples = msaaSamples_;
  msaaAtt.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
  msaaAtt.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE; // Resolved, not stored
  msaaAtt.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  msaaAtt.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  msaaAtt.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  msaaAtt.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  // Attachment 1: Resolve target (swapchain image)
  VkAttachmentDescription resolveAtt{};
  resolveAtt.format = swapFormat_;
  resolveAtt.samples = VK_SAMPLE_COUNT_1_BIT;
  resolveAtt.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  resolveAtt.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  resolveAtt.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  resolveAtt.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  resolveAtt.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  resolveAtt.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

  VkAttachmentDescription attachments[] = {msaaAtt, resolveAtt};

  VkAttachmentReference colorRef{};
  colorRef.attachment = 0; // MSAA color
  colorRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  VkAttachmentReference resolveRef{};
  resolveRef.attachment = 1; // Resolve target
  resolveRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  VkSubpassDescription sub{};
  sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
  sub.colorAttachmentCount = 1;
  sub.pColorAttachments = &colorRef;
  sub.pResolveAttachments = &resolveRef;

  VkSubpassDependency dep{};
  dep.srcSubpass = VK_SUBPASS_EXTERNAL;
  dep.dstSubpass = 0;
  dep.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dep.srcAccessMask = 0;
  dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

  VkRenderPassCreateInfo rpci{};
  rpci.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  rpci.attachmentCount = 2;
  rpci.pAttachments = attachments;
  rpci.subpassCount = 1;
  rpci.pSubpasses = &sub;
  rpci.dependencyCount = 1;
  rpci.pDependencies = &dep;

  VK_CHECK(vkCreateRenderPass(device_, &rpci, nullptr, &renderPass_));
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// GRAPHICS PIPELINE
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createPipeline() {
  // Shader modules
  VkShaderModuleCreateInfo vsci{};
  vsci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  vsci.codeSize = vert_shader_spv_size;
  vsci.pCode = vert_shader_spv;

  VkShaderModule vertModule;
  VK_CHECK(vkCreateShaderModule(device_, &vsci, nullptr, &vertModule));

  VkShaderModuleCreateInfo fsci{};
  fsci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  fsci.codeSize = frag_shader_spv_size;
  fsci.pCode = frag_shader_spv;

  VkShaderModule fragModule;
  VK_CHECK(vkCreateShaderModule(device_, &fsci, nullptr, &fragModule));

  VkPipelineShaderStageCreateInfo stages[2]{};
  stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
  stages[0].module = vertModule;
  stages[0].pName = "main";
  stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
  stages[1].module = fragModule;
  stages[1].pName = "main";

  // Vertex input: float2 position + float4 color
  VkVertexInputBindingDescription binding{};
  binding.binding = 0;
  binding.stride = sizeof(StrokeVertex);
  binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

  VkVertexInputAttributeDescription attrs[2]{};
  attrs[0].location = 0; // inPosition (vec2)
  attrs[0].binding = 0;
  attrs[0].format = VK_FORMAT_R32G32_SFLOAT;
  attrs[0].offset = offsetof(StrokeVertex, x);
  attrs[1].location = 1; // inColor (vec4)
  attrs[1].binding = 0;
  attrs[1].format = VK_FORMAT_R32G32B32A32_SFLOAT;
  attrs[1].offset = offsetof(StrokeVertex, r);

  VkPipelineVertexInputStateCreateInfo vertexInput{};
  vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  vertexInput.vertexBindingDescriptionCount = 1;
  vertexInput.pVertexBindingDescriptions = &binding;
  vertexInput.vertexAttributeDescriptionCount = 2;
  vertexInput.pVertexAttributeDescriptions = attrs;

  VkPipelineInputAssemblyStateCreateInfo assembly{};
  assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  assembly.primitiveRestartEnable = VK_FALSE;

  // Viewport + scissor (dynamic)
  VkViewport viewport{};
  viewport.width = (float)swapExtent_.width;
  viewport.height = (float)swapExtent_.height;
  viewport.maxDepth = 1.0f;

  VkRect2D scissor{};
  scissor.extent = swapExtent_;

  VkPipelineViewportStateCreateInfo vpState{};
  vpState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  vpState.viewportCount = 1;
  vpState.pViewports = &viewport;
  vpState.scissorCount = 1;
  vpState.pScissors = &scissor;

  // Rasterizer
  VkPipelineRasterizationStateCreateInfo raster{};
  raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  raster.polygonMode = VK_POLYGON_MODE_FILL;
  raster.cullMode = VK_CULL_MODE_NONE;
  raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
  raster.lineWidth = 1.0f;

  // No MSAA (keep it simple for v1)
  VkPipelineMultisampleStateCreateInfo msaa{};
  msaa.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  msaa.rasterizationSamples = msaaSamples_;

  // Blending: overwrite mode (prevents alpha accumulation at joints)
  VkPipelineColorBlendAttachmentState blendAtt{};
  blendAtt.blendEnable = VK_TRUE;
  blendAtt.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
  blendAtt.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  blendAtt.colorBlendOp = VK_BLEND_OP_ADD;
  blendAtt.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
  blendAtt.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  blendAtt.alphaBlendOp = VK_BLEND_OP_ADD;
  blendAtt.colorWriteMask = VK_COLOR_COMPONENT_R_BIT |
                            VK_COLOR_COMPONENT_G_BIT |
                            VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

  VkPipelineColorBlendStateCreateInfo blend{};
  blend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  blend.attachmentCount = 1;
  blend.pAttachments = &blendAtt;

  // Push constants: mat4 transform (64 bytes)
  VkPushConstantRange pushRange{};
  pushRange.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
  pushRange.offset = 0;
  pushRange.size = 64; // sizeof(mat4)

  VkPipelineLayoutCreateInfo layoutCI{};
  layoutCI.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  layoutCI.pushConstantRangeCount = 1;
  layoutCI.pPushConstantRanges = &pushRange;

  VK_CHECK(
      vkCreatePipelineLayout(device_, &layoutCI, nullptr, &pipelineLayout_));

  // Dynamic viewport/scissor for resize
  VkDynamicState dynStates[] = {
      VK_DYNAMIC_STATE_VIEWPORT,
      VK_DYNAMIC_STATE_SCISSOR,
  };
  VkPipelineDynamicStateCreateInfo dynState{};
  dynState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  dynState.dynamicStateCount = 2;
  dynState.pDynamicStates = dynStates;

  VkGraphicsPipelineCreateInfo pci{};
  pci.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  pci.stageCount = 2;
  pci.pStages = stages;
  pci.pVertexInputState = &vertexInput;
  pci.pInputAssemblyState = &assembly;
  pci.pViewportState = &vpState;
  pci.pRasterizationState = &raster;
  pci.pMultisampleState = &msaa;
  pci.pColorBlendState = &blend;
  pci.pDynamicState = &dynState;
  pci.layout = pipelineLayout_;
  pci.renderPass = renderPass_;
  pci.subpass = 0;

  VkResult r = vkCreateGraphicsPipelines(device_, VK_NULL_HANDLE, 1, &pci,
                                         nullptr, &pipeline_);
  vkDestroyShaderModule(device_, vertModule, nullptr);
  vkDestroyShaderModule(device_, fragModule, nullptr);

  if (r != VK_SUCCESS) {
    LOGE("vkCreateGraphicsPipelines failed: %d", r);
    return false;
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// FRAMEBUFFERS
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createFramebuffers() {
  framebuffers_.resize(swapViews_.size());
  for (size_t i = 0; i < swapViews_.size(); i++) {
    // MSAA: attach both multisampled color and resolve target
    VkImageView attachments[] = {msaaView_, swapViews_[i]};
    VkFramebufferCreateInfo fci{};
    fci.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    fci.renderPass = renderPass_;
    fci.attachmentCount = 2;
    fci.pAttachments = attachments;
    fci.width = swapExtent_.width;
    fci.height = swapExtent_.height;
    fci.layers = 1;
    VK_CHECK(vkCreateFramebuffer(device_, &fci, nullptr, &framebuffers_[i]));
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// COMMAND POOL + BUFFER
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createCommandPool() {
  VkCommandPoolCreateInfo cpci{};
  cpci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  cpci.queueFamilyIndex = queueFamily_;
  VK_CHECK(vkCreateCommandPool(device_, &cpci, nullptr, &cmdPool_));

  VkCommandBufferAllocateInfo cbai{};
  cbai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  cbai.commandPool = cmdPool_;
  cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  cbai.commandBufferCount = MAX_FRAMES_IN_FLIGHT;
  VK_CHECK(vkAllocateCommandBuffers(device_, &cbai, cmdBuffers_));
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// VERTEX BUFFER (host-visible, pre-allocated)
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createVertexBuffer() {
  VkDeviceSize size = MAX_VERTICES * sizeof(StrokeVertex);

  VkBufferCreateInfo bci{};
  bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  bci.size = size;
  bci.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
  bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  VK_CHECK(vkCreateBuffer(device_, &bci, nullptr, &vertexBuffer_));

  VkMemoryRequirements memReq;
  vkGetBufferMemoryRequirements(device_, vertexBuffer_, &memReq);

  VkMemoryAllocateInfo mai{};
  mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  mai.allocationSize = memReq.size;
  mai.memoryTypeIndex = findMemoryType(
      memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  VK_CHECK(vkAllocateMemory(device_, &mai, nullptr, &vertexMemory_));
  VK_CHECK(vkBindBufferMemory(device_, vertexBuffer_, vertexMemory_, 0));

  // 🚀 Persistent mapping — stays mapped for the lifetime of the buffer
  VK_CHECK(
      vkMapMemory(device_, vertexMemory_, 0, size, 0, &mappedVertexMemory_));
  return true;
}

uint32_t VkStrokeRenderer::findMemoryType(uint32_t typeFilter,
                                          VkMemoryPropertyFlags props) {
  VkPhysicalDeviceMemoryProperties memProps;
  vkGetPhysicalDeviceMemoryProperties(physDevice_, &memProps);
  for (uint32_t i = 0; i < memProps.memoryTypeCount; i++) {
    if ((typeFilter & (1 << i)) &&
        (memProps.memoryTypes[i].propertyFlags & props) == props) {
      return i;
    }
  }
  LOGE("Failed to find suitable memory type");
  return 0;
}

// ═══════════════════════════════════════════════════════════════════
// SYNC OBJECTS
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::createSyncObjects() {
  VkSemaphoreCreateInfo sci{};
  sci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
  VkFenceCreateInfo fci{};
  fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  fci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

  for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
    VK_CHECK(vkCreateSemaphore(device_, &sci, nullptr, &imageAvailSems_[i]));
    VK_CHECK(vkCreateSemaphore(device_, &sci, nullptr, &renderDoneSems_[i]));
    VK_CHECK(vkCreateFence(device_, &fci, nullptr, &frameFences_[i]));
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// TESSELLATION — polyline → circle-at-point + segment quads
// Matches Dart/Skia StrokeCap.round + StrokeJoin.round exactly.
// ═══════════════════════════════════════════════════════════════════

void VkStrokeRenderer::tessellateStroke(const float *points, int pointCount,
                                        float r, float g, float b, float a,
                                        float strokeWidth, int pointStartIndex,
                                        int totalPoints,
                                        std::vector<StrokeVertex> &outVerts) {
  if (pointCount < 2)
    return;

  // ─── Ballpoint: constant width matching Dart ──────────────────
  constexpr float WIDTH_FACTOR = 0.925f;
  constexpr int TAPER_POINTS = 3;
  constexpr float TAPER_START_FRAC = 0.60f;

  float baseHalfW = strokeWidth * WIDTH_FACTOR * 0.5f;

  for (int i = 0; i < pointCount; i++) {
    float px = points[i * 3];
    float py = points[i * 3 + 1];

    int globalIdx = pointStartIndex + i;

    // ─── Width = base × entry taper ─────────────────────────────
    float halfW = baseHalfW;
    if (globalIdx < TAPER_POINTS) {
      float t = (float)(globalIdx + 1) / (float)TAPER_POINTS;
      float ease = 1.0f - (1.0f - t) * (1.0f - t) * (1.0f - t);
      halfW *= TAPER_START_FRAC + (1.0f - TAPER_START_FRAC) * ease;
    }

    // ─── Circle at every point (round join/cap) ─────────────────
    generateCircle(px, py, halfW, r, g, b, a, outVerts);

    // ─── Segment quad to next point ─────────────────────────────
    if (i < pointCount - 1) {
      float nx = points[(i + 1) * 3];
      float ny = points[(i + 1) * 3 + 1];

      float dx = nx - px;
      float dy = ny - py;
      float len = std::sqrt(dx * dx + dy * dy);
      if (len < 0.001f)
        continue;

      // Next point's taper width
      int nextGlobal = globalIdx + 1;
      float nHalfW = baseHalfW;
      if (nextGlobal < TAPER_POINTS) {
        float t = (float)(nextGlobal + 1) / (float)TAPER_POINTS;
        float ease = 1.0f - (1.0f - t) * (1.0f - t) * (1.0f - t);
        nHalfW *= TAPER_START_FRAC + (1.0f - TAPER_START_FRAC) * ease;
      }

      float perpX = -dy / len;
      float perpY = dx / len;

      outVerts.push_back({px + perpX * halfW, py + perpY * halfW, r, g, b, a});
      outVerts.push_back({px - perpX * halfW, py - perpY * halfW, r, g, b, a});
      outVerts.push_back(
          {nx + perpX * nHalfW, ny + perpY * nHalfW, r, g, b, a});
      outVerts.push_back({px - perpX * halfW, py - perpY * halfW, r, g, b, a});
      outVerts.push_back(
          {nx + perpX * nHalfW, ny + perpY * nHalfW, r, g, b, a});
      outVerts.push_back(
          {nx - perpX * nHalfW, ny - perpY * nHalfW, r, g, b, a});
    }
  }
}

void VkStrokeRenderer::generateCircle(float cx, float cy, float radius, float r,
                                      float g, float b, float a,
                                      std::vector<StrokeVertex> &outVerts) {
  // Adaptive segment count based on radius (more segments for larger strokes)
  int segments = std::max(8, std::min(24, (int)(radius * 2.0f)));

  for (int i = 0; i < segments; i++) {
    float a0 = 2.0f * (float)M_PI * (float)i / (float)segments;
    float a1 = 2.0f * (float)M_PI * (float)(i + 1) / (float)segments;

    float x0 = cx + radius * std::cos(a0);
    float y0 = cy + radius * std::sin(a0);
    float x1 = cx + radius * std::cos(a1);
    float y1 = cy + radius * std::sin(a1);

    // Triangle fan: center + two arc points
    outVerts.push_back({cx, cy, r, g, b, a});
    outVerts.push_back({x0, y0, r, g, b, a});
    outVerts.push_back({x1, y1, r, g, b, a});
  }
}

// ═══════════════════════════════════════════════════════════════════
// SET TRANSFORM
// ═══════════════════════════════════════════════════════════════════

void VkStrokeRenderer::setTransform(const float *matrix4x4) {
  memcpy(transform_, matrix4x4, 16 * sizeof(float));
}

// ═══════════════════════════════════════════════════════════════════
// RENDER FRAME
// ═══════════════════════════════════════════════════════════════════

void VkStrokeRenderer::updateAndRender(const float *points, int pointCount,
                                       float r, float g, float b, float a,
                                       float strokeWidth, int totalPoints) {
  if (!initialized_ || pointCount < 2 || !mappedVertexMemory_)
    return;

  // 🎨 Track global point index for tapering
  int startIndex = totalAccumulatedPoints_;
  totalAccumulatedPoints_ += pointCount;
  // Overlap by 1 for segment continuity
  if (startIndex > 0) {
    startIndex -= 1;
  }

  // 🚀 INCREMENTAL: Tessellate directly into accumulated buffer
  size_t prevSize = accumulatedVerts_.size();
  tessellateStroke(points, pointCount, r, g, b, a, strokeWidth, startIndex,
                   totalPoints, accumulatedVerts_);

  if (accumulatedVerts_.size() > MAX_VERTICES) {
    accumulatedVerts_.resize(prevSize); // Undo if overflow
    return;
  }
  vertexCount_ = static_cast<uint32_t>(accumulatedVerts_.size());

  // 🚀 Only upload the NEW delta (not the whole buffer)
  size_t newCount = accumulatedVerts_.size() - prevSize;
  if (newCount > 0) {
    auto *dst =
        reinterpret_cast<StrokeVertex *>(mappedVertexMemory_) + prevSize;
    memcpy(dst, accumulatedVerts_.data() + prevSize,
           newCount * sizeof(StrokeVertex));
  }

  // ─── Stats: measure actual render work time ─────────────────
  statsActive_ = true;
  statsDrawCalls_ = 1;
  statsTotalFrames_++;
  auto frameStart = std::chrono::steady_clock::now();

  // ─── Record + submit (double-buffered) ─────────────────────
  uint32_t f = currentFrame_;
  vkWaitForFences(device_, 1, &frameFences_[f], VK_TRUE, UINT64_MAX);
  vkResetFences(device_, 1, &frameFences_[f]);

  uint32_t imageIndex;
  VkResult acqResult =
      vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, imageAvailSems_[f],
                            VK_NULL_HANDLE, &imageIndex);
  if (acqResult == VK_ERROR_OUT_OF_DATE_KHR) {
    resize(width_, height_);
    return;
  }

  vkResetCommandBuffer(cmdBuffers_[f], 0);

  VkCommandBufferBeginInfo beginInfo{};
  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cmdBuffers_[f], &beginInfo);

  VkClearValue clearVals[2]{};
  clearVals[0].color = {{0.0f, 0.0f, 0.0f, 0.0f}};
  clearVals[1].color = {{0.0f, 0.0f, 0.0f, 0.0f}};

  VkRenderPassBeginInfo rpbi{};
  rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  rpbi.renderPass = renderPass_;
  rpbi.framebuffer = framebuffers_[imageIndex];
  rpbi.renderArea.extent = swapExtent_;
  rpbi.clearValueCount = 2;
  rpbi.pClearValues = clearVals;

  vkCmdBeginRenderPass(cmdBuffers_[f], &rpbi, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(cmdBuffers_[f], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_);

  VkViewport vp{};
  vp.width = (float)swapExtent_.width;
  vp.height = (float)swapExtent_.height;
  vp.maxDepth = 1.0f;
  vkCmdSetViewport(cmdBuffers_[f], 0, 1, &vp);

  VkRect2D sc{};
  sc.extent = swapExtent_;
  vkCmdSetScissor(cmdBuffers_[f], 0, 1, &sc);

  vkCmdPushConstants(cmdBuffers_[f], pipelineLayout_,
                     VK_SHADER_STAGE_VERTEX_BIT, 0, 64, transform_);

  VkDeviceSize offset = 0;
  vkCmdBindVertexBuffers(cmdBuffers_[f], 0, 1, &vertexBuffer_, &offset);
  vkCmdDraw(cmdBuffers_[f], vertexCount_, 1, 0, 0);

  vkCmdEndRenderPass(cmdBuffers_[f]);
  vkEndCommandBuffer(cmdBuffers_[f]);

  VkPipelineStageFlags waitStage =
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  VkSubmitInfo si{};
  si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  si.waitSemaphoreCount = 1;
  si.pWaitSemaphores = &imageAvailSems_[f];
  si.pWaitDstStageMask = &waitStage;
  si.commandBufferCount = 1;
  si.pCommandBuffers = &cmdBuffers_[f];
  si.signalSemaphoreCount = 1;
  si.pSignalSemaphores = &renderDoneSems_[f];
  vkQueueSubmit(queue_, 1, &si, frameFences_[f]);

  VkPresentInfoKHR pi{};
  pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  pi.waitSemaphoreCount = 1;
  pi.pWaitSemaphores = &renderDoneSems_[f];
  pi.swapchainCount = 1;
  pi.pSwapchains = &swapchain_;
  pi.pImageIndices = &imageIndex;
  vkQueuePresentKHR(queue_, &pi);

  // ─── End stats timing ─────────────────────────────────────
  auto frameEnd = std::chrono::steady_clock::now();
  auto frameUs = std::chrono::duration_cast<std::chrono::microseconds>(
                     frameEnd - frameStart)
                     .count();
  frameTimesUs_.push_back(static_cast<float>(frameUs));
  if ((int)frameTimesUs_.size() > STATS_MAX_SAMPLES) {
    frameTimesUs_.erase(frameTimesUs_.begin());
  }

  currentFrame_ = (currentFrame_ + 1) % MAX_FRAMES_IN_FLIGHT;
}

void VkStrokeRenderer::clearFrame() {
  if (!initialized_)
    return;

  accumulatedVerts_.clear();
  vertexCount_ = 0;
  totalAccumulatedPoints_ = 0;
  statsActive_ = false;
  hasLastFrameTime_ = false;

  uint32_t f = currentFrame_;
  vkWaitForFences(device_, 1, &frameFences_[f], VK_TRUE, UINT64_MAX);
  vkResetFences(device_, 1, &frameFences_[f]);

  uint32_t imageIndex;
  VkResult acqResult =
      vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, imageAvailSems_[f],
                            VK_NULL_HANDLE, &imageIndex);
  if (acqResult != VK_SUCCESS)
    return;

  vkResetCommandBuffer(cmdBuffers_[f], 0);

  VkCommandBufferBeginInfo beginInfo{};
  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cmdBuffers_[f], &beginInfo);

  VkClearValue clearVals[2]{};
  clearVals[0].color = {{0.0f, 0.0f, 0.0f, 0.0f}};
  clearVals[1].color = {{0.0f, 0.0f, 0.0f, 0.0f}};

  VkRenderPassBeginInfo rpbi{};
  rpbi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  rpbi.renderPass = renderPass_;
  rpbi.framebuffer = framebuffers_[imageIndex];
  rpbi.renderArea.extent = swapExtent_;
  rpbi.clearValueCount = 2;
  rpbi.pClearValues = clearVals;

  vkCmdBeginRenderPass(cmdBuffers_[f], &rpbi, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdEndRenderPass(cmdBuffers_[f]);
  vkEndCommandBuffer(cmdBuffers_[f]);

  VkPipelineStageFlags waitStage =
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  VkSubmitInfo si{};
  si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  si.waitSemaphoreCount = 1;
  si.pWaitSemaphores = &imageAvailSems_[f];
  si.pWaitDstStageMask = &waitStage;
  si.commandBufferCount = 1;
  si.pCommandBuffers = &cmdBuffers_[f];
  si.signalSemaphoreCount = 1;
  si.pSignalSemaphores = &renderDoneSems_[f];
  vkQueueSubmit(queue_, 1, &si, frameFences_[f]);

  VkPresentInfoKHR pi{};
  pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  pi.waitSemaphoreCount = 1;
  pi.pWaitSemaphores = &renderDoneSems_[f];
  pi.swapchainCount = 1;
  pi.pSwapchains = &swapchain_;
  pi.pImageIndices = &imageIndex;
  vkQueuePresentKHR(queue_, &pi);

  currentFrame_ = (currentFrame_ + 1) % MAX_FRAMES_IN_FLIGHT;
}

// ═══════════════════════════════════════════════════════════════════
// RESIZE
// ═══════════════════════════════════════════════════════════════════

bool VkStrokeRenderer::resize(int width, int height) {
  if (!initialized_)
    return false;
  vkDeviceWaitIdle(device_);

  width_ = width;
  height_ = height;

  destroySwapchain();
  if (!createSwapchain())
    return false;
  if (!createFramebuffers())
    return false;

  LOGI("VkStrokeRenderer resized: %dx%d", width, height);
  return true;
}

// ═══════════════════════════════════════════════════════════════════
// CLEANUP
// ═══════════════════════════════════════════════════════════════════

void VkStrokeRenderer::destroySwapchain() {
  for (auto fb : framebuffers_)
    vkDestroyFramebuffer(device_, fb, nullptr);
  framebuffers_.clear();
  destroyMsaaResources();
  for (auto iv : swapViews_)
    vkDestroyImageView(device_, iv, nullptr);
  swapViews_.clear();
  if (swapchain_)
    vkDestroySwapchainKHR(device_, swapchain_, nullptr);
  swapchain_ = VK_NULL_HANDLE;
  swapImages_.clear();
}

bool VkStrokeRenderer::createMsaaResources() {
  VkImageCreateInfo ici{};
  ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  ici.imageType = VK_IMAGE_TYPE_2D;
  ici.format = swapFormat_;
  ici.extent = {swapExtent_.width, swapExtent_.height, 1};
  ici.mipLevels = 1;
  ici.arrayLayers = 1;
  ici.samples = msaaSamples_;
  ici.tiling = VK_IMAGE_TILING_OPTIMAL;
  ici.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
              VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
  ici.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

  VK_CHECK(vkCreateImage(device_, &ici, nullptr, &msaaImage_));

  VkMemoryRequirements memReq;
  vkGetImageMemoryRequirements(device_, msaaImage_, &memReq);

  VkMemoryAllocateInfo mai{};
  mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  mai.allocationSize = memReq.size;
  // Prefer LAZILY_ALLOCATED for transient MSAA (GPU-only, never stored)
  uint32_t memType = findMemoryType(memReq.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT |
                                        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  if (memType == 0) {
    // Fallback to regular device-local
    memType = findMemoryType(memReq.memoryTypeBits,
                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  }
  mai.memoryTypeIndex = memType;
  VK_CHECK(vkAllocateMemory(device_, &mai, nullptr, &msaaMemory_));
  VK_CHECK(vkBindImageMemory(device_, msaaImage_, msaaMemory_, 0));

  VkImageViewCreateInfo vci{};
  vci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  vci.image = msaaImage_;
  vci.viewType = VK_IMAGE_VIEW_TYPE_2D;
  vci.format = swapFormat_;
  vci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  vci.subresourceRange.levelCount = 1;
  vci.subresourceRange.layerCount = 1;
  VK_CHECK(vkCreateImageView(device_, &vci, nullptr, &msaaView_));

  LOGI("MSAA 4x resources created");
  return true;
}

void VkStrokeRenderer::destroyMsaaResources() {
  if (msaaView_)
    vkDestroyImageView(device_, msaaView_, nullptr);
  if (msaaImage_)
    vkDestroyImage(device_, msaaImage_, nullptr);
  if (msaaMemory_)
    vkFreeMemory(device_, msaaMemory_, nullptr);
  msaaView_ = VK_NULL_HANDLE;
  msaaImage_ = VK_NULL_HANDLE;
  msaaMemory_ = VK_NULL_HANDLE;
}

void VkStrokeRenderer::destroy() {
  if (!instance_)
    return;
  if (device_)
    vkDeviceWaitIdle(device_);

  for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
    if (frameFences_[i])
      vkDestroyFence(device_, frameFences_[i], nullptr);
    if (imageAvailSems_[i])
      vkDestroySemaphore(device_, imageAvailSems_[i], nullptr);
    if (renderDoneSems_[i])
      vkDestroySemaphore(device_, renderDoneSems_[i], nullptr);
  }

  if (vertexBuffer_)
    vkDestroyBuffer(device_, vertexBuffer_, nullptr);
  if (vertexMemory_) {
    if (mappedVertexMemory_) {
      vkUnmapMemory(device_, vertexMemory_);
      mappedVertexMemory_ = nullptr;
    }
    vkFreeMemory(device_, vertexMemory_, nullptr);
  }

  if (cmdPool_)
    vkDestroyCommandPool(device_, cmdPool_, nullptr);
  if (pipeline_)
    vkDestroyPipeline(device_, pipeline_, nullptr);
  if (pipelineLayout_)
    vkDestroyPipelineLayout(device_, pipelineLayout_, nullptr);
  if (renderPass_)
    vkDestroyRenderPass(device_, renderPass_, nullptr);

  destroySwapchain();

  if (surface_)
    vkDestroySurfaceKHR(instance_, surface_, nullptr);
  if (device_)
    vkDestroyDevice(device_, nullptr);
  if (instance_)
    vkDestroyInstance(instance_, nullptr);

  if (window_)
    ANativeWindow_release(window_);

  instance_ = VK_NULL_HANDLE;
  device_ = VK_NULL_HANDLE;
  surface_ = VK_NULL_HANDLE;
  window_ = nullptr;
  initialized_ = false;
  frameTimesUs_.clear();
  statsDrawCalls_ = 0;
  statsTotalFrames_ = 0;
  statsActive_ = false;
  hasLastFrameTime_ = false;

  LOGI("VkStrokeRenderer destroyed");
}

// ═══════════════════════════════════════════════════════════════════
// PERFORMANCE STATS
// ═══════════════════════════════════════════════════════════════════

VkStrokeStats VkStrokeRenderer::getStats() const {
  VkStrokeStats s{};

  // Compute percentiles from rolling frame time buffer
  if (!frameTimesUs_.empty()) {
    std::vector<float> sorted(frameTimesUs_);
    std::sort(sorted.begin(), sorted.end());
    int n = (int)sorted.size();
    s.frameTimeP50Us = sorted[n / 2];
    s.frameTimeP90Us = sorted[std::min((int)(n * 0.9f), n - 1)];
    s.frameTimeP99Us = sorted[std::min((int)(n * 0.99f), n - 1)];
  }

  s.vertexCount = vertexCount_;
  s.drawCalls = statsDrawCalls_;
  s.swapchainImages = (uint32_t)swapImages_.size();
  s.totalFrames = statsTotalFrames_;
  s.active = statsActive_;

  // Device info
  strncpy(s.deviceName, deviceProps_.deviceName, sizeof(s.deviceName) - 1);
  s.deviceName[sizeof(s.deviceName) - 1] = '\0';
  s.apiVersionMajor = VK_VERSION_MAJOR(deviceProps_.apiVersion);
  s.apiVersionMinor = VK_VERSION_MINOR(deviceProps_.apiVersion);
  s.apiVersionPatch = VK_VERSION_PATCH(deviceProps_.apiVersion);

  return s;
}
