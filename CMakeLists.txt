cmake_minimum_required(VERSION 3.20)
project(CSVLint VERSION 0.1.0 LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

set(NPP_MACOS_DIR "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus-macos")
set(SCINTILLA_INCLUDE "${NPP_MACOS_DIR}/scintilla/include")
set(NPP_PLUGIN_INCLUDE "${NPP_MACOS_DIR}/src")

add_library(CSVLint SHARED
    src/PluginEntry.mm
    src/CsvLintPanel.mm
    src/engine/CsvSchemaIni.cpp
    src/engine/CsvDefinition.cpp
    src/engine/CsvAnalyze.cpp
    src/engine/CsvValidate.cpp
    src/engine/DateTimeMask.cpp
)
target_include_directories(CSVLint PRIVATE
    ${NPP_PLUGIN_INCLUDE}
    ${SCINTILLA_INCLUDE}
    src
    src/engine)
target_link_libraries(CSVLint PRIVATE
    "-framework Cocoa")
set_target_properties(CSVLint PROPERTIES PREFIX "" SUFFIX ".dylib")
# Stamp version into the dylib Mach-O current_version (Plugins Admin reads it).
target_link_options(CSVLint PRIVATE "-Wl,-current_version,${PROJECT_VERSION}")
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/Library/Application Support/Nextpad++/plugins/CSVLint")
install(TARGETS CSVLint DESTINATION "${PLUGIN_INSTALL_DIR}")
