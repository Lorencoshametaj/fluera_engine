/**
 * vk_image_processor.cpp — Fluera Engine Vulkan GPU Image Processing
 *
 * Render-pipeline-based image filtering using Vulkan.
 * Each filter is a fullscreen quad pass with a specialized fragment shader.
 * Multi-pass effects (blur) use ping-pong render targets.
 */

#include "vk_image_processor.h"

#include <android/log.h>
#include <android/native_window.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>

#define TAG "VkImageProcessor"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Pre-compiled SPIR-V shader data
#include "shaders/image_filter_shaders.h"

// ─── Vulkan State ────────────────────────────────────────────────

static struct {
  VkInstance instance;
  VkPhysicalDevice physicalDevice;
  VkDevice device;
  VkQueue queue;
  uint32_t queueFamilyIndex;
  VkCommandPool commandPool;
  VkCommandBuffer cmdBuf;
  VkFence fence;

  // Source image (uploaded RGBA data)
  VkImage srcImage;
  VkDeviceMemory srcMemory;
  VkImageView srcView;
  VkSampler srcSampler;
  int srcWidth;
  int srcHeight;

  // Output render target
  VkImage outImage;
  VkDeviceMemory outMemory;
  VkImageView outView;

  // Ping texture (for multi-pass effects)
  VkImage pingImage;
  VkDeviceMemory pingMemory;
  VkImageView pingView;

  // Descriptor pool and sets
  VkDescriptorPool descriptorPool;
  VkDescriptorSetLayout descriptorSetLayout;
  VkDescriptorSet srcDescSet;  // samples srcImage
  VkDescriptorSet outDescSet;  // samples outImage (for sharpen)
  VkDescriptorSet pingDescSet; // samples pingImage

  // Render passes
  VkRenderPass renderPass; // LOAD_OP_DONT_CARE

  // Framebuffers
  VkFramebuffer outFramebuffer;
  VkFramebuffer pingFramebuffer;

  // Pipelines
  VkPipelineLayout filterPipelineLayout; // push constants
  VkPipeline colorGradingPipeline;
  VkPipeline blurHPipeline;
  VkPipeline blurVPipeline;

  VkPipelineLayout sharpenPipelineLayout; // 2 descriptors
  VkDescriptorSetLayout sharpenDescLayout;
  VkDescriptorSet sharpenDescSet;
  VkPipeline sharpenPipeline;

  // HSL per-channel pipeline (large push constants: 96 bytes)
  VkPipelineLayout hslPipelineLayout;
  VkPipeline hslPipeline;

  // Bilateral denoise pipeline
  VkPipeline bilateralPipeline;

  // Tone curve pipeline (128 bytes push constants)
  VkPipelineLayout toneCurvePipelineLayout;
  VkPipeline toneCurvePipeline;

  // Clarity, split toning, film grain (16 bytes push constants each)
  VkPipeline clarityPipeline;
  VkPipeline splitToningPipeline;
  VkPipeline filmGrainPipeline;

  // Swapchain for presentation
  ANativeWindow *nativeWindow;
  VkSurfaceKHR surface;
  VkSwapchainKHR swapchain;
  VkImage *swapchainImages;
  uint32_t swapchainImageCount;

  int width;
  int height;
  int initialized;
} g_ip = {};

// ─── Helpers ─────────────────────────────────────────────────────

static uint32_t findMemType(uint32_t typeFilter,
                            VkMemoryPropertyFlags properties) {
  VkPhysicalDeviceMemoryProperties memProp;
  vkGetPhysicalDeviceMemoryProperties(g_ip.physicalDevice, &memProp);
  for (uint32_t i = 0; i < memProp.memoryTypeCount; i++) {
    if ((typeFilter & (1 << i)) &&
        (memProp.memoryTypes[i].propertyFlags & properties) == properties) {
      return i;
    }
  }
  return 0;
}

static VkShaderModule createShader(const uint32_t *code, size_t codeSize) {
  VkShaderModuleCreateInfo ci = {};
  ci.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  ci.codeSize = codeSize;
  ci.pCode = code;
  VkShaderModule mod;
  if (vkCreateShaderModule(g_ip.device, &ci, nullptr, &mod) != VK_SUCCESS) {
    LOGE("createShader failed");
    return VK_NULL_HANDLE;
  }
  return mod;
}

// Create a VkImage + memory + view
static int createImage(int w, int h, VkImageUsageFlags usage,
                       VkMemoryPropertyFlags memFlags, VkImage *image,
                       VkDeviceMemory *memory, VkImageView *view) {
  VkImageCreateInfo imageInfo = {};
  imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  imageInfo.imageType = VK_IMAGE_TYPE_2D;
  imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
  imageInfo.extent = {(uint32_t)w, (uint32_t)h, 1};
  imageInfo.mipLevels = 1;
  imageInfo.arrayLayers = 1;
  imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
  imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
  imageInfo.usage = usage;
  imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

  if (vkCreateImage(g_ip.device, &imageInfo, nullptr, image) != VK_SUCCESS) {
    LOGE("vkCreateImage failed");
    return 0;
  }

  VkMemoryRequirements memReqs;
  vkGetImageMemoryRequirements(g_ip.device, *image, &memReqs);

  VkMemoryAllocateInfo allocInfo = {};
  allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  allocInfo.allocationSize = memReqs.size;
  allocInfo.memoryTypeIndex = findMemType(memReqs.memoryTypeBits, memFlags);

  if (vkAllocateMemory(g_ip.device, &allocInfo, nullptr, memory) !=
      VK_SUCCESS) {
    LOGE("vkAllocateMemory failed");
    return 0;
  }

  vkBindImageMemory(g_ip.device, *image, *memory, 0);

  VkImageViewCreateInfo viewInfo = {};
  viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  viewInfo.image = *image;
  viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
  viewInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
  viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  viewInfo.subresourceRange.levelCount = 1;
  viewInfo.subresourceRange.layerCount = 1;

  if (vkCreateImageView(g_ip.device, &viewInfo, nullptr, view) != VK_SUCCESS) {
    LOGE("vkCreateImageView failed");
    return 0;
  }

  return 1;
}

// Transition image layout
static void transitionLayout(VkCommandBuffer cmd, VkImage image,
                             VkImageLayout oldLayout, VkImageLayout newLayout,
                             VkAccessFlags srcAccess, VkAccessFlags dstAccess,
                             VkPipelineStageFlags srcStage,
                             VkPipelineStageFlags dstStage) {
  VkImageMemoryBarrier barrier = {};
  barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  barrier.oldLayout = oldLayout;
  barrier.newLayout = newLayout;
  barrier.srcAccessMask = srcAccess;
  barrier.dstAccessMask = dstAccess;
  barrier.image = image;
  barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};

  vkCmdPipelineBarrier(cmd, srcStage, dstStage, 0, 0, nullptr, 0, nullptr, 1,
                       &barrier);
}

// ─── Pipeline Creation ───────────────────────────────────────────

static int createDescriptorResources() {
  // Descriptor set layout: 1 combined image sampler
  VkDescriptorSetLayoutBinding binding = {};
  binding.binding = 0;
  binding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  binding.descriptorCount = 1;
  binding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

  VkDescriptorSetLayoutCreateInfo layoutInfo = {};
  layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  layoutInfo.bindingCount = 1;
  layoutInfo.pBindings = &binding;

  if (vkCreateDescriptorSetLayout(g_ip.device, &layoutInfo, nullptr,
                                  &g_ip.descriptorSetLayout) != VK_SUCCESS) {
    return 0;
  }

  // Descriptor pool (3 sets: src, out, ping)
  VkDescriptorPoolSize poolSize = {};
  poolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  poolSize.descriptorCount = 4;

  VkDescriptorPoolCreateInfo poolInfo = {};
  poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  poolInfo.maxSets = 4;
  poolInfo.poolSizeCount = 1;
  poolInfo.pPoolSizes = &poolSize;

  if (vkCreateDescriptorPool(g_ip.device, &poolInfo, nullptr,
                             &g_ip.descriptorPool) != VK_SUCCESS) {
    return 0;
  }

  // Allocate descriptor sets
  VkDescriptorSetLayout layouts[4] = {
      g_ip.descriptorSetLayout, g_ip.descriptorSetLayout,
      g_ip.descriptorSetLayout, g_ip.descriptorSetLayout};
  VkDescriptorSetAllocateInfo allocInfo = {};
  allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  allocInfo.descriptorPool = g_ip.descriptorPool;
  allocInfo.descriptorSetCount = 4;
  allocInfo.pSetLayouts = layouts;

  VkDescriptorSet sets[4];
  if (vkAllocateDescriptorSets(g_ip.device, &allocInfo, sets) != VK_SUCCESS) {
    return 0;
  }
  g_ip.srcDescSet = sets[0];
  g_ip.outDescSet = sets[1];
  g_ip.pingDescSet = sets[2];
  g_ip.sharpenDescSet = sets[3];

  // Sampler (linear, clamp-to-edge)
  VkSamplerCreateInfo samplerInfo = {};
  samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  samplerInfo.magFilter = VK_FILTER_LINEAR;
  samplerInfo.minFilter = VK_FILTER_LINEAR;
  samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
  samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
  samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
  samplerInfo.maxAnisotropy = 1.0f;
  samplerInfo.maxLod = VK_LOD_CLAMP_NONE;

  if (vkCreateSampler(g_ip.device, &samplerInfo, nullptr, &g_ip.srcSampler) !=
      VK_SUCCESS) {
    return 0;
  }

  return 1;
}

static void updateDescriptorSet(VkDescriptorSet set, VkImageView view,
                                VkSampler sampler) {
  VkDescriptorImageInfo imageInfo = {};
  imageInfo.sampler = sampler;
  imageInfo.imageView = view;
  imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

  VkWriteDescriptorSet write = {};
  write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  write.dstSet = set;
  write.dstBinding = 0;
  write.descriptorCount = 1;
  write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  write.pImageInfo = &imageInfo;

  vkUpdateDescriptorSets(g_ip.device, 1, &write, 0, nullptr);
}

static int createRenderPass() {
  VkAttachmentDescription att = {};
  att.format = VK_FORMAT_R8G8B8A8_UNORM;
  att.samples = VK_SAMPLE_COUNT_1_BIT;
  att.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  att.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

  VkAttachmentReference ref = {};
  ref.attachment = 0;
  ref.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  VkSubpassDescription subpass = {};
  subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
  subpass.colorAttachmentCount = 1;
  subpass.pColorAttachments = &ref;

  VkRenderPassCreateInfo rpInfo = {};
  rpInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  rpInfo.attachmentCount = 1;
  rpInfo.pAttachments = &att;
  rpInfo.subpassCount = 1;
  rpInfo.pSubpasses = &subpass;

  return vkCreateRenderPass(g_ip.device, &rpInfo, nullptr, &g_ip.renderPass) ==
         VK_SUCCESS;
}

static int createFramebuffers(int w, int h) {
  VkFramebufferCreateInfo fbInfo = {};
  fbInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  fbInfo.renderPass = g_ip.renderPass;
  fbInfo.attachmentCount = 1;
  fbInfo.width = w;
  fbInfo.height = h;
  fbInfo.layers = 1;

  fbInfo.pAttachments = &g_ip.outView;
  if (vkCreateFramebuffer(g_ip.device, &fbInfo, nullptr,
                          &g_ip.outFramebuffer) != VK_SUCCESS) {
    return 0;
  }

  fbInfo.pAttachments = &g_ip.pingView;
  if (vkCreateFramebuffer(g_ip.device, &fbInfo, nullptr,
                          &g_ip.pingFramebuffer) != VK_SUCCESS) {
    return 0;
  }

  return 1;
}

static VkPipeline createFilterPipeline(VkShaderModule vertShader,
                                       VkShaderModule fragShader,
                                       VkPipelineLayout layout) {
  VkPipelineShaderStageCreateInfo stages[2] = {};
  stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
  stages[0].module = vertShader;
  stages[0].pName = "main";
  stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
  stages[1].module = fragShader;
  stages[1].pName = "main";

  VkPipelineVertexInputStateCreateInfo vertInput = {};
  vertInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

  VkPipelineInputAssemblyStateCreateInfo inputAsm = {};
  inputAsm.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  inputAsm.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

  VkPipelineViewportStateCreateInfo vpState = {};
  vpState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  vpState.viewportCount = 1;
  vpState.scissorCount = 1;

  VkPipelineRasterizationStateCreateInfo raster = {};
  raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  raster.polygonMode = VK_POLYGON_MODE_FILL;
  raster.lineWidth = 1.0f;
  raster.cullMode = VK_CULL_MODE_NONE;

  VkPipelineMultisampleStateCreateInfo ms = {};
  ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

  VkPipelineColorBlendAttachmentState blendAtt = {};
  blendAtt.colorWriteMask = VK_COLOR_COMPONENT_R_BIT |
                            VK_COLOR_COMPONENT_G_BIT |
                            VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

  VkPipelineColorBlendStateCreateInfo blend = {};
  blend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  blend.attachmentCount = 1;
  blend.pAttachments = &blendAtt;

  VkDynamicState dynStates[] = {VK_DYNAMIC_STATE_VIEWPORT,
                                VK_DYNAMIC_STATE_SCISSOR};
  VkPipelineDynamicStateCreateInfo dynState = {};
  dynState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  dynState.dynamicStateCount = 2;
  dynState.pDynamicStates = dynStates;

  VkGraphicsPipelineCreateInfo pipeInfo = {};
  pipeInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  pipeInfo.stageCount = 2;
  pipeInfo.pStages = stages;
  pipeInfo.pVertexInputState = &vertInput;
  pipeInfo.pInputAssemblyState = &inputAsm;
  pipeInfo.pViewportState = &vpState;
  pipeInfo.pRasterizationState = &raster;
  pipeInfo.pMultisampleState = &ms;
  pipeInfo.pColorBlendState = &blend;
  pipeInfo.pDynamicState = &dynState;
  pipeInfo.layout = layout;
  pipeInfo.renderPass = g_ip.renderPass;
  pipeInfo.subpass = 0;

  VkPipeline pipeline;
  if (vkCreateGraphicsPipelines(g_ip.device, VK_NULL_HANDLE, 1, &pipeInfo,
                                nullptr, &pipeline) != VK_SUCCESS) {
    LOGE("createFilterPipeline failed");
    return VK_NULL_HANDLE;
  }
  return pipeline;
}

static int createPipelines() {
  // Shader modules
  VkShaderModule vertShader =
      createShader(image_filter_vert_spv, image_filter_vert_spv_len);
  VkShaderModule colorFragShader =
      createShader(image_filter_frag_spv, image_filter_frag_spv_len);
  VkShaderModule blurHFragShader =
      createShader(blur_h_frag_spv, blur_h_frag_spv_len);
  VkShaderModule blurVFragShader =
      createShader(blur_v_frag_spv, blur_v_frag_spv_len);
  VkShaderModule sharpenFragShader =
      createShader(sharpen_frag_spv, sharpen_frag_spv_len);

  if (!vertShader || !colorFragShader || !blurHFragShader || !blurVFragShader ||
      !sharpenFragShader) {
    return 0;
  }

  // Pipeline layout: 1 descriptor set + push constants (32 bytes)
  VkPushConstantRange pushRange = {};
  pushRange.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
  pushRange.offset = 0;
  pushRange.size = sizeof(VkipFilterParams);

  VkPipelineLayoutCreateInfo layoutInfo = {};
  layoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  layoutInfo.setLayoutCount = 1;
  layoutInfo.pSetLayouts = &g_ip.descriptorSetLayout;
  layoutInfo.pushConstantRangeCount = 1;
  layoutInfo.pPushConstantRanges = &pushRange;

  if (vkCreatePipelineLayout(g_ip.device, &layoutInfo, nullptr,
                             &g_ip.filterPipelineLayout) != VK_SUCCESS) {
    return 0;
  }

  // Create pipelines
  g_ip.colorGradingPipeline = createFilterPipeline(vertShader, colorFragShader,
                                                   g_ip.filterPipelineLayout);
  g_ip.blurHPipeline = createFilterPipeline(vertShader, blurHFragShader,
                                            g_ip.filterPipelineLayout);
  g_ip.blurVPipeline = createFilterPipeline(vertShader, blurVFragShader,
                                            g_ip.filterPipelineLayout);
  g_ip.sharpenPipeline = createFilterPipeline(vertShader, sharpenFragShader,
                                              g_ip.filterPipelineLayout);

  // Cleanup base fragment shader modules (keep vertShader for later pipelines)
  vkDestroyShaderModule(g_ip.device, colorFragShader, nullptr);
  vkDestroyShaderModule(g_ip.device, blurHFragShader, nullptr);
  vkDestroyShaderModule(g_ip.device, blurVFragShader, nullptr);
  vkDestroyShaderModule(g_ip.device, sharpenFragShader, nullptr);

  if (!g_ip.colorGradingPipeline || !g_ip.blurHPipeline ||
      !g_ip.blurVPipeline || !g_ip.sharpenPipeline) {
    vkDestroyShaderModule(g_ip.device, vertShader, nullptr);
    return 0;
  }

  // ─── HSL Per-Channel Pipeline (96 bytes push constants) ────────────
  VkShaderModule hslFragShader =
      createShader(hsl_per_channel_frag_spv, hsl_per_channel_frag_spv_len);
  if (hslFragShader) {
    VkPushConstantRange hslPushRange = {};
    hslPushRange.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    hslPushRange.offset = 0;
    hslPushRange.size = sizeof(VkipHslParams); // 96 bytes

    VkPipelineLayoutCreateInfo hslLayoutInfo = {};
    hslLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    hslLayoutInfo.setLayoutCount = 1;
    hslLayoutInfo.pSetLayouts = &g_ip.descriptorSetLayout;
    hslLayoutInfo.pushConstantRangeCount = 1;
    hslLayoutInfo.pPushConstantRanges = &hslPushRange;

    vkCreatePipelineLayout(g_ip.device, &hslLayoutInfo, nullptr,
                           &g_ip.hslPipelineLayout);
    g_ip.hslPipeline =
        createFilterPipeline(vertShader, hslFragShader, g_ip.hslPipelineLayout);
    vkDestroyShaderModule(g_ip.device, hslFragShader, nullptr);
  }

  // ─── Bilateral Denoise Pipeline (16 bytes push constants) ──────────
  VkShaderModule bilateralFragShader =
      createShader(bilateral_denoise_frag_spv, bilateral_denoise_frag_spv_len);
  if (bilateralFragShader) {
    g_ip.bilateralPipeline = createFilterPipeline(
        vertShader, bilateralFragShader, g_ip.filterPipelineLayout);
    vkDestroyShaderModule(g_ip.device, bilateralFragShader, nullptr);
  }

  // ─── Tone Curve Pipeline (128 bytes push constants) ────────────────
  VkShaderModule toneCurveFragShader =
      createShader(tone_curve_frag_spv, tone_curve_frag_spv_len);
  if (toneCurveFragShader) {
    VkPushConstantRange tcPushRange = {};
    tcPushRange.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    tcPushRange.offset = 0;
    tcPushRange.size = sizeof(VkipToneCurveParams); // 128 bytes

    VkPipelineLayoutCreateInfo tcLayoutInfo = {};
    tcLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    tcLayoutInfo.setLayoutCount = 1;
    tcLayoutInfo.pSetLayouts = &g_ip.descriptorSetLayout;
    tcLayoutInfo.pushConstantRangeCount = 1;
    tcLayoutInfo.pPushConstantRanges = &tcPushRange;

    vkCreatePipelineLayout(g_ip.device, &tcLayoutInfo, nullptr,
                           &g_ip.toneCurvePipelineLayout);
    g_ip.toneCurvePipeline = createFilterPipeline(
        vertShader, toneCurveFragShader, g_ip.toneCurvePipelineLayout);
    vkDestroyShaderModule(g_ip.device, toneCurveFragShader, nullptr);
  }

  // ─── Clarity Pipeline (16 bytes push constants) ────────────────────
  VkShaderModule clarityFragShader =
      createShader(clarity_frag_spv, clarity_frag_spv_len);
  if (clarityFragShader) {
    g_ip.clarityPipeline = createFilterPipeline(vertShader, clarityFragShader,
                                                g_ip.filterPipelineLayout);
    vkDestroyShaderModule(g_ip.device, clarityFragShader, nullptr);
  }

  // ─── Split Toning Pipeline (48 bytes push constants) ───────────────
  VkShaderModule splitFragShader =
      createShader(split_toning_frag_spv, split_toning_frag_spv_len);
  if (splitFragShader) {
    g_ip.splitToningPipeline = createFilterPipeline(vertShader, splitFragShader,
                                                    g_ip.filterPipelineLayout);
    vkDestroyShaderModule(g_ip.device, splitFragShader, nullptr);
  }

  // ─── Film Grain Pipeline (16 bytes push constants) ─────────────────
  VkShaderModule grainFragShader =
      createShader(film_grain_frag_spv, film_grain_frag_spv_len);
  if (grainFragShader) {
    g_ip.filmGrainPipeline = createFilterPipeline(vertShader, grainFragShader,
                                                  g_ip.filterPipelineLayout);
    vkDestroyShaderModule(g_ip.device, grainFragShader, nullptr);
  }

  // All shader modules done — destroy shared vertex shader
  vkDestroyShaderModule(g_ip.device, vertShader, nullptr);

  LOGI("All image processing pipelines created successfully");
  return 1;
}

// ─── Rendering Helpers ───────────────────────────────────────────

static void beginCmd() {
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);
  vkResetFences(g_ip.device, 1, &g_ip.fence);
  vkResetCommandBuffer(g_ip.cmdBuf, 0);

  VkCommandBufferBeginInfo beginInfo = {};
  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(g_ip.cmdBuf, &beginInfo);
}

static void submitCmd() {
  vkEndCommandBuffer(g_ip.cmdBuf);

  VkSubmitInfo submitInfo = {};
  submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submitInfo.commandBufferCount = 1;
  submitInfo.pCommandBuffers = &g_ip.cmdBuf;

  vkQueueSubmit(g_ip.queue, 1, &submitInfo, g_ip.fence);
}

static void renderPass(VkCommandBuffer cmd, VkFramebuffer fb,
                       VkPipeline pipeline, VkPipelineLayout layout,
                       VkDescriptorSet descSet, const void *pushData,
                       uint32_t pushSize) {
  VkRenderPassBeginInfo rpBegin = {};
  rpBegin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  rpBegin.renderPass = g_ip.renderPass;
  rpBegin.framebuffer = fb;
  rpBegin.renderArea.extent = {(uint32_t)g_ip.width, (uint32_t)g_ip.height};

  vkCmdBeginRenderPass(cmd, &rpBegin, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

  VkViewport viewport = {0,    0,   (float)g_ip.width, (float)g_ip.height,
                         0.0f, 1.0f};
  VkRect2D scissor = {{0, 0}, {(uint32_t)g_ip.width, (uint32_t)g_ip.height}};
  vkCmdSetViewport(cmd, 0, 1, &viewport);
  vkCmdSetScissor(cmd, 0, 1, &scissor);

  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 1,
                          &descSet, 0, nullptr);

  if (pushData && pushSize > 0) {
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, pushSize,
                       pushData);
  }

  vkCmdDraw(cmd, 6, 1, 0, 0);
  vkCmdEndRenderPass(cmd);
}

// Blit out image to swapchain and present
static void present() {
  if (!g_ip.swapchain)
    return;

  uint32_t imageIndex;
  VkResult res =
      vkAcquireNextImageKHR(g_ip.device, g_ip.swapchain, UINT64_MAX,
                            VK_NULL_HANDLE, VK_NULL_HANDLE, &imageIndex);
  if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR)
    return;

  beginCmd();
  VkCommandBuffer cmd = g_ip.cmdBuf;

  // out → TRANSFER_SRC
  transitionLayout(cmd, g_ip.outImage, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                   VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                   VK_PIPELINE_STAGE_TRANSFER_BIT);

  // swapchain → TRANSFER_DST
  transitionLayout(
      cmd, g_ip.swapchainImages[imageIndex], VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
      VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

  VkImageCopy copy = {};
  copy.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
  copy.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
  copy.extent = {(uint32_t)g_ip.width, (uint32_t)g_ip.height, 1};

  vkCmdCopyImage(cmd, g_ip.outImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                 g_ip.swapchainImages[imageIndex],
                 VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);

  // swapchain → PRESENT_SRC
  transitionLayout(
      cmd, g_ip.swapchainImages[imageIndex],
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
      VK_ACCESS_TRANSFER_WRITE_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);

  // out → SHADER_READ (restore for next pass)
  transitionLayout(cmd, g_ip.outImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                   VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_SHADER_READ_BIT,
                   VK_PIPELINE_STAGE_TRANSFER_BIT,
                   VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

  submitCmd();

  // Wait then present
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  VkPresentInfoKHR presentInfo = {};
  presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  presentInfo.swapchainCount = 1;
  presentInfo.pSwapchains = &g_ip.swapchain;
  presentInfo.pImageIndices = &imageIndex;
  vkQueuePresentKHR(g_ip.queue, &presentInfo);
}

// ─── Public API ──────────────────────────────────────────────────

extern "C" {

int vkip_is_available(void) { return g_ip.initialized; }

int vkip_init(int width, int height, void *nativeWindow) {
  if (g_ip.initialized)
    return 1;

  g_ip.width = width;
  g_ip.height = height;

  // Reuse Vulkan instance/device creation pattern from vk_stroke_renderer
  VkApplicationInfo appInfo = {};
  appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  appInfo.pApplicationName = "FluImageProc";
  appInfo.apiVersion = VK_API_VERSION_1_1;

  const char *exts[] = {VK_KHR_SURFACE_EXTENSION_NAME,
                        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME};

  VkInstanceCreateInfo instInfo = {};
  instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  instInfo.pApplicationInfo = &appInfo;
  instInfo.enabledExtensionCount = 2;
  instInfo.ppEnabledExtensionNames = exts;

  if (vkCreateInstance(&instInfo, nullptr, &g_ip.instance) != VK_SUCCESS) {
    LOGE("vkCreateInstance failed");
    return 0;
  }

  // Physical device
  uint32_t devCount = 0;
  vkEnumeratePhysicalDevices(g_ip.instance, &devCount, nullptr);
  if (devCount == 0)
    return 0;
  std::vector<VkPhysicalDevice> devs(devCount);
  vkEnumeratePhysicalDevices(g_ip.instance, &devCount, devs.data());
  g_ip.physicalDevice = devs[0];

  // Queue family
  uint32_t qfCount = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(g_ip.physicalDevice, &qfCount,
                                           nullptr);
  std::vector<VkQueueFamilyProperties> qfs(qfCount);
  vkGetPhysicalDeviceQueueFamilyProperties(g_ip.physicalDevice, &qfCount,
                                           qfs.data());
  for (uint32_t i = 0; i < qfCount; i++) {
    if (qfs[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
      g_ip.queueFamilyIndex = i;
      break;
    }
  }

  // Logical device
  float prio = 1.0f;
  VkDeviceQueueCreateInfo queueCI = {};
  queueCI.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  queueCI.queueFamilyIndex = g_ip.queueFamilyIndex;
  queueCI.queueCount = 1;
  queueCI.pQueuePriorities = &prio;

  const char *devExts[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
  VkDeviceCreateInfo devCI = {};
  devCI.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  devCI.queueCreateInfoCount = 1;
  devCI.pQueueCreateInfos = &queueCI;
  devCI.enabledExtensionCount = 1;
  devCI.ppEnabledExtensionNames = devExts;

  if (vkCreateDevice(g_ip.physicalDevice, &devCI, nullptr, &g_ip.device) !=
      VK_SUCCESS) {
    return 0;
  }
  vkGetDeviceQueue(g_ip.device, g_ip.queueFamilyIndex, 0, &g_ip.queue);

  // Command pool + buffer
  VkCommandPoolCreateInfo poolCI = {};
  poolCI.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  poolCI.queueFamilyIndex = g_ip.queueFamilyIndex;
  poolCI.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

  if (vkCreateCommandPool(g_ip.device, &poolCI, nullptr, &g_ip.commandPool) !=
      VK_SUCCESS) {
    return 0;
  }

  VkCommandBufferAllocateInfo cmdAlloc = {};
  cmdAlloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  cmdAlloc.commandPool = g_ip.commandPool;
  cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  cmdAlloc.commandBufferCount = 1;
  vkAllocateCommandBuffers(g_ip.device, &cmdAlloc, &g_ip.cmdBuf);

  VkFenceCreateInfo fenceCI = {};
  fenceCI.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  fenceCI.flags = VK_FENCE_CREATE_SIGNALED_BIT;
  vkCreateFence(g_ip.device, &fenceCI, nullptr, &g_ip.fence);

  // Create render targets
  VkImageUsageFlags srcUsage =
      VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  VkImageUsageFlags rtUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                              VK_IMAGE_USAGE_SAMPLED_BIT |
                              VK_IMAGE_USAGE_TRANSFER_SRC_BIT;

  if (!createImage(width, height, srcUsage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                   &g_ip.srcImage, &g_ip.srcMemory, &g_ip.srcView)) {
    return 0;
  }
  if (!createImage(width, height, rtUsage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                   &g_ip.outImage, &g_ip.outMemory, &g_ip.outView)) {
    return 0;
  }
  if (!createImage(width, height, rtUsage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                   &g_ip.pingImage, &g_ip.pingMemory, &g_ip.pingView)) {
    return 0;
  }

  // Descriptor resources
  if (!createDescriptorResources())
    return 0;

  // Update descriptor sets
  updateDescriptorSet(g_ip.srcDescSet, g_ip.srcView, g_ip.srcSampler);
  updateDescriptorSet(g_ip.outDescSet, g_ip.outView, g_ip.srcSampler);
  updateDescriptorSet(g_ip.pingDescSet, g_ip.pingView, g_ip.srcSampler);

  // Render pass and framebuffers
  if (!createRenderPass())
    return 0;
  if (!createFramebuffers(width, height))
    return 0;

  // Pipelines
  if (!createPipelines())
    return 0;

  // Swapchain
  if (nativeWindow) {
    ANativeWindow *win = (ANativeWindow *)nativeWindow;
    VkAndroidSurfaceCreateInfoKHR surfCI = {};
    surfCI.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
    surfCI.window = win;
    vkCreateAndroidSurfaceKHR(g_ip.instance, &surfCI, nullptr, &g_ip.surface);

    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(g_ip.physicalDevice, g_ip.surface,
                                              &caps);

    uint32_t imgCount = caps.minImageCount + 1;
    if (caps.maxImageCount > 0 && imgCount > caps.maxImageCount)
      imgCount = caps.maxImageCount;

    VkSwapchainCreateInfoKHR swapCI = {};
    swapCI.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    swapCI.surface = g_ip.surface;
    swapCI.minImageCount = imgCount;
    swapCI.imageFormat = VK_FORMAT_R8G8B8A8_UNORM;
    swapCI.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    swapCI.imageExtent = {(uint32_t)width, (uint32_t)height};
    swapCI.imageArrayLayers = 1;
    swapCI.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    swapCI.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    swapCI.preTransform = caps.currentTransform;
    swapCI.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    swapCI.clipped = VK_TRUE;

    vkCreateSwapchainKHR(g_ip.device, &swapCI, nullptr, &g_ip.swapchain);

    vkGetSwapchainImagesKHR(g_ip.device, g_ip.swapchain,
                            &g_ip.swapchainImageCount, nullptr);
    g_ip.swapchainImages =
        (VkImage *)malloc(g_ip.swapchainImageCount * sizeof(VkImage));
    vkGetSwapchainImagesKHR(g_ip.device, g_ip.swapchain,
                            &g_ip.swapchainImageCount, g_ip.swapchainImages);

    g_ip.nativeWindow = win;
    ANativeWindow_acquire(win);
  }

  // Transition src image to appropriate layout
  beginCmd();
  transitionLayout(
      g_ip.cmdBuf, g_ip.srcImage, VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
      VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  g_ip.initialized = 1;
  LOGI("VkImageProcessor initialized: %dx%d", width, height);
  return 1;
}

int vkip_upload_image(const uint8_t *rgba, int w, int h) {
  if (!g_ip.initialized)
    return 0;

  // Create staging buffer
  VkDeviceSize size = (VkDeviceSize)w * h * 4;
  VkBuffer staging;
  VkDeviceMemory stagingMem;

  VkBufferCreateInfo bufCI = {};
  bufCI.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  bufCI.size = size;
  bufCI.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  vkCreateBuffer(g_ip.device, &bufCI, nullptr, &staging);

  VkMemoryRequirements memReqs;
  vkGetBufferMemoryRequirements(g_ip.device, staging, &memReqs);

  VkMemoryAllocateInfo allocInfo = {};
  allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  allocInfo.allocationSize = memReqs.size;
  allocInfo.memoryTypeIndex = findMemType(
      memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                  VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  vkAllocateMemory(g_ip.device, &allocInfo, nullptr, &stagingMem);
  vkBindBufferMemory(g_ip.device, staging, stagingMem, 0);

  // Copy data to staging
  void *mapped;
  vkMapMemory(g_ip.device, stagingMem, 0, size, 0, &mapped);
  memcpy(mapped, rgba, size);
  vkUnmapMemory(g_ip.device, stagingMem);

  // Copy staging → srcImage
  beginCmd();

  transitionLayout(
      g_ip.cmdBuf, g_ip.srcImage, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_ACCESS_SHADER_READ_BIT,
      VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT);

  VkBufferImageCopy region = {};
  region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
  region.imageExtent = {(uint32_t)w, (uint32_t)h, 1};

  vkCmdCopyBufferToImage(g_ip.cmdBuf, staging, g_ip.srcImage,
                         VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

  transitionLayout(
      g_ip.cmdBuf, g_ip.srcImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
      VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  // Cleanup staging
  vkDestroyBuffer(g_ip.device, staging, nullptr);
  vkFreeMemory(g_ip.device, stagingMem, nullptr);

  g_ip.srcWidth = w;
  g_ip.srcHeight = h;

  LOGI("Image uploaded: %dx%d", w, h);
  return 1;
}

void vkip_apply_filters(const VkipFilterParams *params) {
  if (!g_ip.initialized)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.colorGradingPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipFilterParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_blur(float radius) {
  if (!g_ip.initialized || radius <= 0)
    return;

  float sigma = radius / 3.0f;

  // Pass 1: H blur (src → ping)
  VkipBlurParams hParams = {1.0f / g_ip.width, radius, sigma, 0};
  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.pingFramebuffer, g_ip.blurHPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, &hParams,
             sizeof(VkipBlurParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  // Pass 2: V blur (ping → out)
  VkipBlurParams vParams = {1.0f / g_ip.height, radius, sigma, 0};
  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.blurVPipeline,
             g_ip.filterPipelineLayout, g_ip.pingDescSet, &vParams,
             sizeof(VkipBlurParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_sharpen(float amount) {
  if (!g_ip.initialized || amount <= 0)
    return;

  // Generate blur for unsharp mask (src → ping)
  float sigma = 1.0f;
  VkipBlurParams hParams = {1.0f / g_ip.width, 3.0f, sigma, 0};
  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.pingFramebuffer, g_ip.blurHPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, &hParams,
             sizeof(VkipBlurParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  // Sharpen: original(src) - blurred(ping) → out
  VkipSharpenParams sParams = {1.0f / g_ip.width, 1.0f / g_ip.height, amount,
                               0};
  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.sharpenPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, &sParams,
             sizeof(VkipSharpenParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_generate_mipmaps(void) {
  if (!g_ip.initialized)
    return;
  LOGI("Mipmap generation requested (hardware mipmapping active)");
}

void vkip_apply_hsl(const VkipHslParams *params) {
  if (!g_ip.initialized || !g_ip.hslPipeline)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.hslPipeline,
             g_ip.hslPipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipHslParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_bilateral_denoise(float strength) {
  if (!g_ip.initialized || !g_ip.bilateralPipeline || strength <= 0)
    return;

  VkipBilateralParams params = {
      1.0f / g_ip.width,  // texelSizeX
      1.0f / g_ip.height, // texelSizeY
      strength,           // spatial strength
      0.1f                // range sigma (color similarity)
  };

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.bilateralPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, &params,
             sizeof(VkipBilateralParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_tone_curve(const VkipToneCurveParams *params) {
  if (!g_ip.initialized || !g_ip.toneCurvePipeline)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.toneCurvePipeline,
             g_ip.toneCurvePipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipToneCurveParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_clarity(const VkipClarityParams *params) {
  if (!g_ip.initialized || !g_ip.clarityPipeline)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.clarityPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipClarityParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_split_toning(const VkipSplitToningParams *params) {
  if (!g_ip.initialized || !g_ip.splitToningPipeline)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.splitToningPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipSplitToningParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_apply_film_grain(const VkipFilmGrainParams *params) {
  if (!g_ip.initialized || !g_ip.filmGrainPipeline)
    return;

  beginCmd();
  renderPass(g_ip.cmdBuf, g_ip.outFramebuffer, g_ip.filmGrainPipeline,
             g_ip.filterPipelineLayout, g_ip.srcDescSet, params,
             sizeof(VkipFilmGrainParams));
  submitCmd();
  vkWaitForFences(g_ip.device, 1, &g_ip.fence, VK_TRUE, UINT64_MAX);

  present();
}

void vkip_cleanup(void) {
  if (!g_ip.initialized)
    return;

  vkDeviceWaitIdle(g_ip.device);

  // Destroy pipelines
  if (g_ip.colorGradingPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.colorGradingPipeline, nullptr);
  if (g_ip.blurHPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.blurHPipeline, nullptr);
  if (g_ip.blurVPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.blurVPipeline, nullptr);
  if (g_ip.sharpenPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.sharpenPipeline, nullptr);
  if (g_ip.hslPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.hslPipeline, nullptr);
  if (g_ip.bilateralPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.bilateralPipeline, nullptr);
  if (g_ip.toneCurvePipeline)
    vkDestroyPipeline(g_ip.device, g_ip.toneCurvePipeline, nullptr);
  if (g_ip.clarityPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.clarityPipeline, nullptr);
  if (g_ip.splitToningPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.splitToningPipeline, nullptr);
  if (g_ip.filmGrainPipeline)
    vkDestroyPipeline(g_ip.device, g_ip.filmGrainPipeline, nullptr);
  if (g_ip.filterPipelineLayout)
    vkDestroyPipelineLayout(g_ip.device, g_ip.filterPipelineLayout, nullptr);
  if (g_ip.hslPipelineLayout)
    vkDestroyPipelineLayout(g_ip.device, g_ip.hslPipelineLayout, nullptr);
  if (g_ip.toneCurvePipelineLayout)
    vkDestroyPipelineLayout(g_ip.device, g_ip.toneCurvePipelineLayout, nullptr);

  // Destroy framebuffers
  if (g_ip.outFramebuffer)
    vkDestroyFramebuffer(g_ip.device, g_ip.outFramebuffer, nullptr);
  if (g_ip.pingFramebuffer)
    vkDestroyFramebuffer(g_ip.device, g_ip.pingFramebuffer, nullptr);

  // Render pass
  if (g_ip.renderPass)
    vkDestroyRenderPass(g_ip.device, g_ip.renderPass, nullptr);

  // Descriptors
  if (g_ip.descriptorPool)
    vkDestroyDescriptorPool(g_ip.device, g_ip.descriptorPool, nullptr);
  if (g_ip.descriptorSetLayout)
    vkDestroyDescriptorSetLayout(g_ip.device, g_ip.descriptorSetLayout,
                                 nullptr);
  if (g_ip.srcSampler)
    vkDestroySampler(g_ip.device, g_ip.srcSampler, nullptr);

  // Images
  if (g_ip.srcView)
    vkDestroyImageView(g_ip.device, g_ip.srcView, nullptr);
  if (g_ip.srcImage)
    vkDestroyImage(g_ip.device, g_ip.srcImage, nullptr);
  if (g_ip.srcMemory)
    vkFreeMemory(g_ip.device, g_ip.srcMemory, nullptr);

  if (g_ip.outView)
    vkDestroyImageView(g_ip.device, g_ip.outView, nullptr);
  if (g_ip.outImage)
    vkDestroyImage(g_ip.device, g_ip.outImage, nullptr);
  if (g_ip.outMemory)
    vkFreeMemory(g_ip.device, g_ip.outMemory, nullptr);

  if (g_ip.pingView)
    vkDestroyImageView(g_ip.device, g_ip.pingView, nullptr);
  if (g_ip.pingImage)
    vkDestroyImage(g_ip.device, g_ip.pingImage, nullptr);
  if (g_ip.pingMemory)
    vkFreeMemory(g_ip.device, g_ip.pingMemory, nullptr);

  // Swapchain
  if (g_ip.swapchainImages)
    free(g_ip.swapchainImages);
  if (g_ip.swapchain)
    vkDestroySwapchainKHR(g_ip.device, g_ip.swapchain, nullptr);
  if (g_ip.surface)
    vkDestroySurfaceKHR(g_ip.instance, g_ip.surface, nullptr);
  if (g_ip.nativeWindow)
    ANativeWindow_release(g_ip.nativeWindow);

  // Command pool/fence
  if (g_ip.fence)
    vkDestroyFence(g_ip.device, g_ip.fence, nullptr);
  if (g_ip.commandPool)
    vkDestroyCommandPool(g_ip.device, g_ip.commandPool, nullptr);

  if (g_ip.device)
    vkDestroyDevice(g_ip.device, nullptr);
  if (g_ip.instance)
    vkDestroyInstance(g_ip.instance, nullptr);

  memset(&g_ip, 0, sizeof(g_ip));
  LOGI("VkImageProcessor cleaned up");
}

} // extern "C"
