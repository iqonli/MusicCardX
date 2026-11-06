cmake_minimum_required(VERSION 3.18)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/.." "${CMAKE_CURRENT_BINARY_DIR}/core")
set(mcx_background_bundled_libraries $<TARGET_FILE:mcx_background> PARENT_SCOPE)
