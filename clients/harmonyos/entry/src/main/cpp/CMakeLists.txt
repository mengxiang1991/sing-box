cmake_minimum_required(VERSION 3.16)
project(sing_box_harmony LANGUAGES CXX)

add_library(singbox SHARED IMPORTED)
set_target_properties(singbox PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libsingbox.so")
add_library(sb_harmony SHARED bridge.cpp)
target_compile_features(sb_harmony PRIVATE cxx_std_17)
target_link_libraries(sb_harmony PRIVATE singbox libace_napi.z.so)
add_library(mh_harmony SHARED mihomo_bridge.cpp)
target_compile_features(mh_harmony PRIVATE cxx_std_17)
target_link_libraries(mh_harmony PRIVATE libace_napi.z.so)
