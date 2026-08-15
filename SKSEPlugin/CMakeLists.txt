cmake_minimum_required(VERSION 3.24)

# ---------------------------------------------------------------------------
# Project
# ---------------------------------------------------------------------------
project(
    SkyrimTwitchExpansion
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# CommonLibSSE-NG is expected to be checked out as a submodule at
# extern/CommonLibSSE-NG (or provided via -DCommonLibSSE_DIR=... / vcpkg overlay).
# See README.md "Building" section.
if(NOT DEFINED CommonLibSSE_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/extern/CommonLibSSE-NG/CMakeLists.txt")
    add_subdirectory(extern/CommonLibSSE-NG CommonLibSSE-NG)
else()
    find_package(CommonLibSSE CONFIG REQUIRED)
endif()

find_package(nlohmann_json CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)

set(SOURCES
    src/main.cpp
    src/Bridge/IPCServer.cpp
    src/Bridge/MessageQueue.h
    src/Hooks/EventSink.cpp
    src/Papyrus/ChaosNativeFunctions.cpp
    src/Settings/Settings.cpp
    src/Update/UpdateChecker.cpp
)

# NOTE: CommonLibSSE-NG's own `add_commonlibsse_plugin` convenience macro is
# only available when the library is consumed as an installed package (via
# find_package). We build it in-tree via add_subdirectory above, so we set
# up the plugin target the plain, standard-CMake way instead.
add_library(${PROJECT_NAME} SHARED ${SOURCES})

set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "SkyrimTwitchExpansion")

target_include_directories(${PROJECT_NAME} PRIVATE src)

target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)

target_link_libraries(
    ${PROJECT_NAME}
    PRIVATE
        CommonLibSSE::CommonLibSSE
        nlohmann_json::nlohmann_json
        spdlog::spdlog
        winhttp
)

target_compile_definitions(
    ${PROJECT_NAME}
    PRIVATE
        STE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        STE_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        STE_VERSION_PATCH=${PROJECT_VERSION_PATCH}
)

# Drop the built DLL straight into the Data/ payload for local iteration
# (installer/install.ps1 does the same for release packaging).
add_custom_command(
    TARGET ${PROJECT_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        "$<TARGET_FILE:${PROJECT_NAME}>"
        "${CMAKE_CURRENT_SOURCE_DIR}/../Data/SKSE/Plugins/$<TARGET_FILE_NAME:${PROJECT_NAME}>"
)
