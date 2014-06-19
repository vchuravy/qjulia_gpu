cmake_minimum_required (VERSION 2.6)
project (ogltest)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR})

find_package(PkgConfig REQUIRED)
pkg_search_module(GLFW REQUIRED glfw3)

find_package(OpenGL REQUIRED)
if(NOT OPENGL_FOUND)
    message("ERROR: OpenGL not found")
endif(NOT OPENGL_FOUND)
set(GL_LIBRARY GL GLU X11)

find_package(OpenCL REQUIRED)
if(NOT OPENCL_FOUND)
    message("ERROR: OpenCL not found")
endif(NOT OPENCL_FOUND)
 
add_executable(gltest gltest.c)

include_directories(${GLFW_INCLUDE_DIRS} ${OPENCL_INCLUDE_DIRS})
 
target_link_libraries(gltest ${GLFW_LIBRARIES} ${GL_LIBRARY} ${OPENCL_LIBRARIES})