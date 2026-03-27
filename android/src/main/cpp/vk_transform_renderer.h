// vk_transform_renderer.h — Vulkan compute pipeline for transform tools
// Manages compute shaders for Liquify, Smudge, and Warp operations.

#pragma once

#include <android/log.h>
#include <android/native_window.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <cstdint>
#include <vector>

#define VK_TRANSFORM_TAG "FlueraVkTransform"
#define LOGI_T(...) __android_log_print(ANDROID_LOG_INFO, VK_TRANSFORM_TAG, __VA_ARGS__)
#define LOGE_T(...) __android_log_print(ANDROID_LOG_ERROR, VK_TRANSFORM_TAG, __VA_ARGS__)

/// Manages Vulkan compute pipelines for Liquify, Smudge, and Warp.
///
/// Unlike VkStrokeRenderer (which uses graphics pipelines for triangle rendering),
/// this class uses compute shaders that operate directly on image textures.
class VkTransformRenderer {
public:
  VkTransformRenderer() = default;
  ~VkTransformRenderer();

  /// Initialize using an existing Vulkan instance and device.
  /// Shares the Vulkan context with VkStrokeRenderer for efficiency.
  bool init(VkInstance instance, VkPhysicalDevice physDevice,
            VkDevice device, VkQueue queue, uint32_t queueFamily,
            int width, int height);

  /// Initialize standalone (creates its own Vulkan context).
  bool initStandalone(int width, int height);

  /// Set the source image data (RGBA, 4 bytes per pixel).
  bool setSourceImage(const uint8_t* data, int width, int height);

  /// Apply liquify deformation using a displacement field.
  /// fieldData: interleaved [dx, dy] pairs, fieldWidth × fieldHeight.
  bool applyLiquify(const float* fieldData, int fieldWidth, int fieldHeight);

  /// Apply smudge along a path of samples.
  /// samples: array of {x, y, radius, strength, r, g, b, a} structs.
  bool applySmudge(const float* samples, int sampleCount);

  /// Apply warp using mesh control points.
  /// meshData: array of {origX, origY, dispX, dispY} per control point.
  bool applyWarp(const float* meshData, int meshCols, int meshRows,
                 float boundsLeft, float boundsTop,
                 float boundsWidth, float boundsHeight);

  /// Read back the output image as RGBA data.
  bool readOutputImage(std::vector<uint8_t>& outData);

  /// Resize the working textures.
  bool resize(int width, int height);

  /// Cleanup all resources.
  void destroy();

  bool isInitialized() const { return initialized_; }

private:
  // ─── Vulkan core ──────────────────────────────────────────────
  VkInstance instance_ = VK_NULL_HANDLE;
  VkPhysicalDevice physDevice_ = VK_NULL_HANDLE;
  VkDevice device_ = VK_NULL_HANDLE;
  VkQueue queue_ = VK_NULL_HANDLE;
  uint32_t queueFamily_ = 0;
  bool ownsInstance_ = false; // Whether we created the instance ourselves

  // ─── Compute pipelines ────────────────────────────────────────
  VkPipelineLayout liquifyPipelineLayout_ = VK_NULL_HANDLE;
  VkPipeline liquifyPipeline_ = VK_NULL_HANDLE;
  VkPipelineLayout smudgePipelineLayout_ = VK_NULL_HANDLE;
  VkPipeline smudgePipeline_ = VK_NULL_HANDLE;
  VkPipelineLayout warpPipelineLayout_ = VK_NULL_HANDLE;
  VkPipeline warpPipeline_ = VK_NULL_HANDLE;

  // ─── Descriptor sets ──────────────────────────────────────────
  VkDescriptorPool descriptorPool_ = VK_NULL_HANDLE;
  VkDescriptorSetLayout liquifyDescLayout_ = VK_NULL_HANDLE;
  VkDescriptorSetLayout smudgeDescLayout_ = VK_NULL_HANDLE;
  VkDescriptorSetLayout warpDescLayout_ = VK_NULL_HANDLE;

  // ─── Images ───────────────────────────────────────────────────
  VkImage srcImage_ = VK_NULL_HANDLE;
  VkImageView srcView_ = VK_NULL_HANDLE;
  VkDeviceMemory srcMemory_ = VK_NULL_HANDLE;
  VkImage dstImage_ = VK_NULL_HANDLE;
  VkImageView dstView_ = VK_NULL_HANDLE;
  VkDeviceMemory dstMemory_ = VK_NULL_HANDLE;

  // ─── Staging buffer (for readback) ────────────────────────────
  VkBuffer stagingBuffer_ = VK_NULL_HANDLE;
  VkDeviceMemory stagingMemory_ = VK_NULL_HANDLE;

  // ─── Command pool ─────────────────────────────────────────────
  VkCommandPool cmdPool_ = VK_NULL_HANDLE;

  // ─── State ────────────────────────────────────────────────────
  int width_ = 0, height_ = 0;
  bool initialized_ = false;

  // ─── Helpers ──────────────────────────────────────────────────
  bool createComputePipelines();
  bool createImages();
  bool createStagingBuffer();
  bool createDescriptorPool();
  bool createStandaloneInstance();
  void destroyImages();

  uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags props);

  /// Run a compute shader with the given pipeline and descriptor writes.
  bool dispatchCompute(VkPipeline pipeline, VkPipelineLayout layout,
                       VkDescriptorSetLayout descLayout,
                       const std::vector<VkWriteDescriptorSet>& writes,
                       const void* pushConstants, uint32_t pushSize,
                       uint32_t groupsX, uint32_t groupsY);
};
