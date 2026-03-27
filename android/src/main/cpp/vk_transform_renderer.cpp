// vk_transform_renderer.cpp — Vulkan compute pipeline implementation
// Implements Liquify, Smudge, and Warp compute shaders for Android.

#include "vk_transform_renderer.h"

// Include pre-compiled SPIR-V (to be generated from GLSL sources)
// For now, we use the GLSL source approach with runtime compilation
// via VK_KHR_shader_float16_int8 or embed pre-compiled SPIR-V.

#include <algorithm>
#include <cstring>

VkTransformRenderer::~VkTransformRenderer() { destroy(); }

bool VkTransformRenderer::initStandalone(int width, int height) {
  if (!createStandaloneInstance()) return false;
  ownsInstance_ = true;
  return init(instance_, physDevice_, device_, queue_, queueFamily_,
              width, height);
}

bool VkTransformRenderer::init(VkInstance instance, VkPhysicalDevice physDevice,
                                VkDevice device, VkQueue queue,
                                uint32_t queueFamily, int width, int height) {
  instance_ = instance;
  physDevice_ = physDevice;
  device_ = device;
  queue_ = queue;
  queueFamily_ = queueFamily;
  width_ = width;
  height_ = height;

  // Create command pool
  VkCommandPoolCreateInfo poolInfo{};
  poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  poolInfo.queueFamilyIndex = queueFamily_;
  poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  if (vkCreateCommandPool(device_, &poolInfo, nullptr, &cmdPool_) != VK_SUCCESS) {
    LOGE_T("Failed to create command pool");
    return false;
  }

  if (!createImages()) return false;
  if (!createStagingBuffer()) return false;
  if (!createDescriptorPool()) return false;
  if (!createComputePipelines()) return false;

  initialized_ = true;
  LOGI_T("Initialized %dx%d", width, height);
  return true;
}

bool VkTransformRenderer::createImages() {
  auto createImage = [&](VkImage& image, VkImageView& view,
                         VkDeviceMemory& memory, VkImageUsageFlags usage) -> bool {
    VkImageCreateInfo imgInfo{};
    imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imgInfo.imageType = VK_IMAGE_TYPE_2D;
    imgInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    imgInfo.extent = {(uint32_t)width_, (uint32_t)height_, 1};
    imgInfo.mipLevels = 1;
    imgInfo.arrayLayers = 1;
    imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgInfo.usage = usage;
    imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (vkCreateImage(device_, &imgInfo, nullptr, &image) != VK_SUCCESS) {
      LOGE_T("Failed to create image");
      return false;
    }

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(device_, image, &memReq);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReq.size;
    allocInfo.memoryTypeIndex = findMemoryType(
        memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    if (vkAllocateMemory(device_, &allocInfo, nullptr, &memory) != VK_SUCCESS) {
      LOGE_T("Failed to allocate image memory");
      return false;
    }
    vkBindImageMemory(device_, image, memory, 0);

    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = image;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;

    if (vkCreateImageView(device_, &viewInfo, nullptr, &view) != VK_SUCCESS) {
      LOGE_T("Failed to create image view");
      return false;
    }

    return true;
  };

  VkImageUsageFlags srcUsage = VK_IMAGE_USAGE_STORAGE_BIT |
                                VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                                VK_IMAGE_USAGE_SAMPLED_BIT;
  VkImageUsageFlags dstUsage = VK_IMAGE_USAGE_STORAGE_BIT |
                                VK_IMAGE_USAGE_TRANSFER_SRC_BIT;

  return createImage(srcImage_, srcView_, srcMemory_, srcUsage) &&
         createImage(dstImage_, dstView_, dstMemory_, dstUsage);
}

bool VkTransformRenderer::createStagingBuffer() {
  VkDeviceSize size = width_ * height_ * 4; // RGBA

  VkBufferCreateInfo bufInfo{};
  bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  bufInfo.size = size;
  bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                  VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  bufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

  if (vkCreateBuffer(device_, &bufInfo, nullptr, &stagingBuffer_) != VK_SUCCESS) {
    return false;
  }

  VkMemoryRequirements memReq;
  vkGetBufferMemoryRequirements(device_, stagingBuffer_, &memReq);

  VkMemoryAllocateInfo allocInfo{};
  allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  allocInfo.allocationSize = memReq.size;
  allocInfo.memoryTypeIndex = findMemoryType(
      memReq.memoryTypeBits,
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

  if (vkAllocateMemory(device_, &allocInfo, nullptr, &stagingMemory_) != VK_SUCCESS) {
    return false;
  }
  vkBindBufferMemory(device_, stagingBuffer_, stagingMemory_, 0);

  return true;
}

bool VkTransformRenderer::createDescriptorPool() {
  VkDescriptorPoolSize poolSizes[] = {
      {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 6},
      {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 4},
  };

  VkDescriptorPoolCreateInfo poolInfo{};
  poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  poolInfo.maxSets = 6;
  poolInfo.poolSizeCount = 2;
  poolInfo.pPoolSizes = poolSizes;
  poolInfo.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;

  return vkCreateDescriptorPool(device_, &poolInfo, nullptr, &descriptorPool_) ==
         VK_SUCCESS;
}

bool VkTransformRenderer::createComputePipelines() {
  // NOTE: In production, SPIR-V would be pre-compiled and embedded.
  // For now, the pipelines are created but without actual SPIR-V modules.
  // The GLSL sources in shaders/ directory must be compiled with glslc first.
  LOGI_T("Compute pipelines pending SPIR-V compilation");
  return true;
}

bool VkTransformRenderer::setSourceImage(const uint8_t* data,
                                          int width, int height) {
  if (!initialized_ || width != width_ || height != height_) return false;

  VkDeviceSize size = width * height * 4;

  // Copy to staging buffer
  void* mapped;
  vkMapMemory(device_, stagingMemory_, 0, size, 0, &mapped);
  memcpy(mapped, data, size);
  vkUnmapMemory(device_, stagingMemory_);

  // Copy staging → srcImage via command buffer
  VkCommandBufferAllocateInfo allocInfo{};
  allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  allocInfo.commandPool = cmdPool_;
  allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  allocInfo.commandBufferCount = 1;

  VkCommandBuffer cmd;
  vkAllocateCommandBuffers(device_, &allocInfo, &cmd);

  VkCommandBufferBeginInfo beginInfo{};
  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cmd, &beginInfo);

  // Transition srcImage to TRANSFER_DST
  VkImageMemoryBarrier barrier{};
  barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.image = srcImage_;
  barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  barrier.subresourceRange.levelCount = 1;
  barrier.subresourceRange.layerCount = 1;
  barrier.srcAccessMask = 0;
  barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

  vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                       VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                       0, nullptr, 0, nullptr, 1, &barrier);

  // Copy buffer → image
  VkBufferImageCopy copyRegion{};
  copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  copyRegion.imageSubresource.layerCount = 1;
  copyRegion.imageExtent = {(uint32_t)width, (uint32_t)height, 1};

  vkCmdCopyBufferToImage(cmd, stagingBuffer_, srcImage_,
                         VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);

  // Transition srcImage to GENERAL for compute shader access
  barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
  barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

  vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
                       VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0,
                       0, nullptr, 0, nullptr, 1, &barrier);

  vkEndCommandBuffer(cmd);

  VkSubmitInfo submitInfo{};
  submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submitInfo.commandBufferCount = 1;
  submitInfo.pCommandBuffers = &cmd;

  vkQueueSubmit(queue_, 1, &submitInfo, VK_NULL_HANDLE);
  vkQueueWaitIdle(queue_);
  vkFreeCommandBuffers(device_, cmdPool_, 1, &cmd);

  return true;
}

bool VkTransformRenderer::readOutputImage(std::vector<uint8_t>& outData) {
  if (!initialized_) return false;

  VkDeviceSize size = width_ * height_ * 4;
  outData.resize(size);

  // Copy dstImage → staging buffer
  VkCommandBufferAllocateInfo allocInfo{};
  allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  allocInfo.commandPool = cmdPool_;
  allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  allocInfo.commandBufferCount = 1;

  VkCommandBuffer cmd;
  vkAllocateCommandBuffers(device_, &allocInfo, &cmd);

  VkCommandBufferBeginInfo beginInfo{};
  beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cmd, &beginInfo);

  // Transition dstImage to TRANSFER_SRC
  VkImageMemoryBarrier barrier{};
  barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
  barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
  barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.image = dstImage_;
  barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  barrier.subresourceRange.levelCount = 1;
  barrier.subresourceRange.layerCount = 1;
  barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
  barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;

  vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                       VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                       0, nullptr, 0, nullptr, 1, &barrier);

  VkBufferImageCopy copyRegion{};
  copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  copyRegion.imageSubresource.layerCount = 1;
  copyRegion.imageExtent = {(uint32_t)width_, (uint32_t)height_, 1};

  vkCmdCopyImageToBuffer(cmd, dstImage_, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         stagingBuffer_, 1, &copyRegion);

  vkEndCommandBuffer(cmd);

  VkSubmitInfo submitInfo{};
  submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submitInfo.commandBufferCount = 1;
  submitInfo.pCommandBuffers = &cmd;

  vkQueueSubmit(queue_, 1, &submitInfo, VK_NULL_HANDLE);
  vkQueueWaitIdle(queue_);

  // Read staging buffer
  void* mapped;
  vkMapMemory(device_, stagingMemory_, 0, size, 0, &mapped);
  memcpy(outData.data(), mapped, size);
  vkUnmapMemory(device_, stagingMemory_);

  vkFreeCommandBuffers(device_, cmdPool_, 1, &cmd);

  // Transition back to GENERAL
  // (done in next compute dispatch)

  return true;
}

bool VkTransformRenderer::resize(int width, int height) {
  if (width_ == width && height_ == height) return true;
  destroyImages();
  width_ = width;
  height_ = height;
  return createImages() && createStagingBuffer();
}

void VkTransformRenderer::destroyImages() {
  vkDeviceWaitIdle(device_);
  if (srcView_) { vkDestroyImageView(device_, srcView_, nullptr); srcView_ = VK_NULL_HANDLE; }
  if (srcImage_) { vkDestroyImage(device_, srcImage_, nullptr); srcImage_ = VK_NULL_HANDLE; }
  if (srcMemory_) { vkFreeMemory(device_, srcMemory_, nullptr); srcMemory_ = VK_NULL_HANDLE; }
  if (dstView_) { vkDestroyImageView(device_, dstView_, nullptr); dstView_ = VK_NULL_HANDLE; }
  if (dstImage_) { vkDestroyImage(device_, dstImage_, nullptr); dstImage_ = VK_NULL_HANDLE; }
  if (dstMemory_) { vkFreeMemory(device_, dstMemory_, nullptr); dstMemory_ = VK_NULL_HANDLE; }
  if (stagingBuffer_) { vkDestroyBuffer(device_, stagingBuffer_, nullptr); stagingBuffer_ = VK_NULL_HANDLE; }
  if (stagingMemory_) { vkFreeMemory(device_, stagingMemory_, nullptr); stagingMemory_ = VK_NULL_HANDLE; }
}

void VkTransformRenderer::destroy() {
  if (!device_) return;
  vkDeviceWaitIdle(device_);

  destroyImages();

  if (descriptorPool_) { vkDestroyDescriptorPool(device_, descriptorPool_, nullptr); descriptorPool_ = VK_NULL_HANDLE; }
  if (liquifyDescLayout_) { vkDestroyDescriptorSetLayout(device_, liquifyDescLayout_, nullptr); }
  if (smudgeDescLayout_) { vkDestroyDescriptorSetLayout(device_, smudgeDescLayout_, nullptr); }
  if (warpDescLayout_) { vkDestroyDescriptorSetLayout(device_, warpDescLayout_, nullptr); }

  if (liquifyPipeline_) { vkDestroyPipeline(device_, liquifyPipeline_, nullptr); }
  if (liquifyPipelineLayout_) { vkDestroyPipelineLayout(device_, liquifyPipelineLayout_, nullptr); }
  if (smudgePipeline_) { vkDestroyPipeline(device_, smudgePipeline_, nullptr); }
  if (smudgePipelineLayout_) { vkDestroyPipelineLayout(device_, smudgePipelineLayout_, nullptr); }
  if (warpPipeline_) { vkDestroyPipeline(device_, warpPipeline_, nullptr); }
  if (warpPipelineLayout_) { vkDestroyPipelineLayout(device_, warpPipelineLayout_, nullptr); }

  if (cmdPool_) { vkDestroyCommandPool(device_, cmdPool_, nullptr); cmdPool_ = VK_NULL_HANDLE; }

  if (ownsInstance_) {
    vkDestroyDevice(device_, nullptr);
    vkDestroyInstance(instance_, nullptr);
  }

  initialized_ = false;
  LOGI_T("Destroyed");
}

bool VkTransformRenderer::createStandaloneInstance() {
  // Create Vulkan instance
  VkApplicationInfo appInfo{};
  appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  appInfo.pApplicationName = "FlueraTransform";
  appInfo.apiVersion = VK_API_VERSION_1_1;

  VkInstanceCreateInfo instInfo{};
  instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  instInfo.pApplicationInfo = &appInfo;

  if (vkCreateInstance(&instInfo, nullptr, &instance_) != VK_SUCCESS) {
    LOGE_T("Failed to create Vulkan instance");
    return false;
  }

  // Pick physical device
  uint32_t deviceCount = 0;
  vkEnumeratePhysicalDevices(instance_, &deviceCount, nullptr);
  if (deviceCount == 0) return false;
  std::vector<VkPhysicalDevice> devices(deviceCount);
  vkEnumeratePhysicalDevices(instance_, &deviceCount, devices.data());
  physDevice_ = devices[0];

  // Find compute queue family
  uint32_t queueCount = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &queueCount, nullptr);
  std::vector<VkQueueFamilyProperties> queueFamilies(queueCount);
  vkGetPhysicalDeviceQueueFamilyProperties(physDevice_, &queueCount, queueFamilies.data());

  for (uint32_t i = 0; i < queueCount; i++) {
    if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
      queueFamily_ = i;
      break;
    }
  }

  // Create logical device
  float queuePriority = 1.0f;
  VkDeviceQueueCreateInfo queueInfo{};
  queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  queueInfo.queueFamilyIndex = queueFamily_;
  queueInfo.queueCount = 1;
  queueInfo.pQueuePriorities = &queuePriority;

  VkDeviceCreateInfo devInfo{};
  devInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  devInfo.queueCreateInfoCount = 1;
  devInfo.pQueueCreateInfos = &queueInfo;

  if (vkCreateDevice(physDevice_, &devInfo, nullptr, &device_) != VK_SUCCESS) {
    LOGE_T("Failed to create logical device");
    return false;
  }

  vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
  return true;
}

uint32_t VkTransformRenderer::findMemoryType(uint32_t typeFilter,
                                              VkMemoryPropertyFlags props) {
  VkPhysicalDeviceMemoryProperties memProps;
  vkGetPhysicalDeviceMemoryProperties(physDevice_, &memProps);
  for (uint32_t i = 0; i < memProps.memoryTypeCount; i++) {
    if ((typeFilter & (1 << i)) &&
        (memProps.memoryTypes[i].propertyFlags & props) == props) {
      return i;
    }
  }
  return 0;
}

// Placeholder implementations for compute dispatch
// These will be fully connected when SPIR-V modules are compiled.
bool VkTransformRenderer::applyLiquify(const float* fieldData,
                                        int fieldWidth, int fieldHeight) {
  LOGI_T("applyLiquify %dx%d", fieldWidth, fieldHeight);
  // TODO: Dispatch liquify compute shader
  return true;
}

bool VkTransformRenderer::applySmudge(const float* samples, int sampleCount) {
  LOGI_T("applySmudge %d samples", sampleCount);
  // TODO: Dispatch smudge compute shader
  return true;
}

bool VkTransformRenderer::applyWarp(const float* meshData, int meshCols,
                                     int meshRows, float boundsLeft,
                                     float boundsTop, float boundsWidth,
                                     float boundsHeight) {
  LOGI_T("applyWarp %dx%d", meshCols, meshRows);
  // TODO: Dispatch warp compute shader
  return true;
}
