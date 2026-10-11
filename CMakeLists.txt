cmake_minimum_required(VERSION 3.14)
project(BitcoindUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME bitcoind_ui
    REP_FILE src/BitcoindBackend.rep
    SOURCES
        src/BitcoindBackend.h
        src/BitcoindBackend.cpp
    INCLUDE_DIRS
        src
)
