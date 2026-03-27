# CMakeLists.txt — Flutter Windows plugin for D3D11 live stroke rendering
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "fluera_engine_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

# Flutter plugin boilerplate
set(PLUGIN_NAME "fluera_engine_plugin")
add_library(${PLUGIN_NAME} SHARED
  "fluera_engine_plugin.cpp"
  "d3d11_stroke_renderer.cpp"
  "d3d11_stroke_overlay_plugin.cpp"
)

# Apply standard Flutter plugin settings
apply_standard_settings(${PLUGIN_NAME})

# Include shared tessellation header
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../shared"
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

# Link D3D11 libraries
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  d3d11
  dxgi
  d3dcompiler
)

# C++17
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)

# Export the plugin
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
