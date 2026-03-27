cmake_minimum_required(VERSION 3.18)
project(fluera_native C CXX)

# RNNoise source files (only what's needed for inference)
set(RNNOISE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/rnnoise)

add_library(fluera_rnnoise SHARED
    rnnoise_jni.c
    ${RNNOISE_DIR}/src/denoise.c
    ${RNNOISE_DIR}/src/nnet.c
    ${RNNOISE_DIR}/src/nnet_default.c
    ${RNNOISE_DIR}/src/rnn.c
    ${RNNOISE_DIR}/src/rnnoise_data.c
    ${RNNOISE_DIR}/src/rnnoise_tables.c
    ${RNNOISE_DIR}/src/pitch.c
    ${RNNOISE_DIR}/src/kiss_fft.c
    ${RNNOISE_DIR}/src/celt_lpc.c
    ${RNNOISE_DIR}/src/parse_lpcnet_weights.c
)

target_include_directories(fluera_rnnoise PRIVATE
    ${RNNOISE_DIR}/include
    ${RNNOISE_DIR}/src
)

# Define HAVE_CONFIG_H so the sources pick up our config.h
target_compile_definitions(fluera_rnnoise PRIVATE HAVE_CONFIG_H)

# Optimize for size on release
target_compile_options(fluera_rnnoise PRIVATE
    -Os
    -fvisibility=hidden
)

# Link Android log library
find_library(log-lib log)
target_link_libraries(fluera_rnnoise ${log-lib})

# ═══════════════════════════════════════════════════════════════════
# Vulkan Stroke Overlay — GPU-accelerated live stroke renderer
# ═══════════════════════════════════════════════════════════════════

add_library(fluera_vk_stroke SHARED
    vk_stroke_renderer.cpp
    vk_jni_bridge.cpp
)

target_include_directories(fluera_vk_stroke PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(fluera_vk_stroke PRIVATE
    VK_USE_PLATFORM_ANDROID_KHR
)

set_target_properties(fluera_vk_stroke PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

target_compile_options(fluera_vk_stroke PRIVATE
    -O2
    -fvisibility=hidden
)

# Link Vulkan, Android, and log libraries.
# Note: -lvulkan is used instead of find_library because Vulkan
# is an NDK system library available at link time for API 24+.
# The Kotlin plugin gracefully prevents loading on API < 24.
find_library(android-lib android)

target_link_libraries(fluera_vk_stroke
    vulkan
    ${android-lib}
    ${log-lib}
)
