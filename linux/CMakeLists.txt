# CMakeLists.txt — Flutter Linux plugin for OpenGL live stroke rendering
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "fluera_engine_plugin")
project(${PROJECT_NAME} LANGUAGES CXX C)

# Flutter plugin boilerplate
set(PLUGIN_NAME "fluera_engine_plugin")
add_library(${PLUGIN_NAME} SHARED
  "fluera_engine_plugin.cc"
  "gl_stroke_renderer.cpp"
  "gl_stroke_overlay_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

# Include shared tessellation header
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../shared"
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

# Find required packages
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED gtk+-3.0)
pkg_check_modules(EGL REQUIRED egl)
pkg_check_modules(GL REQUIRED gl)

target_include_directories(${PLUGIN_NAME} PRIVATE
  ${GTK_INCLUDE_DIRS}
  ${EGL_INCLUDE_DIRS}
  ${GL_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  ${GTK_LIBRARIES}
  ${EGL_LIBRARIES}
  ${GL_LIBRARIES}
)

# C++17
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)

# Export
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
