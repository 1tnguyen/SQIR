set (LIBRARY_NAME xacc-voqc)

include_directories(${CMAKE_CURRENT_SOURCE_DIR})

file (GLOB HEADERS *.hpp)
file (GLOB SRC *.cpp)

usFunctionGetResourceSource(TARGET ${LIBRARY_NAME} OUT SRC)
usFunctionGenerateBundleInit(TARGET ${LIBRARY_NAME} OUT SRC)

add_library(${LIBRARY_NAME} SHARED ${SRC})

set(_bundle_name xacc_voqc_optimizer)
set_target_properties(${LIBRARY_NAME} PROPERTIES
    # This is required for every bundle
    COMPILE_DEFINITIONS US_BUNDLE_NAME=${_bundle_name}
    # This is for convenience, used by other CMake functions
    US_BUNDLE_NAME ${_bundle_name}
    )

# Embed meta-data from a manifest.json file
usFunctionEmbedResources(TARGET ${LIBRARY_NAME}
    WORKING_DIRECTORY
    ${CMAKE_CURRENT_SOURCE_DIR}
    FILES
    manifest.json
    )

target_include_directories(${LIBRARY_NAME} PUBLIC .)

# Add a custum target to build VOQC and install libvoqc.so to ${XACC_DIR}/lib
add_custom_target(voqc ALL)
add_custom_command(
  TARGET   voqc
  COMMAND cd  ${CMAKE_SOURCE_DIR} && make voqc_lib && cp ${CMAKE_SOURCE_DIR}/VOQC/_build/default/extraction/libvoqc.so ${XACC_DIR}/lib
)

add_dependencies(${LIBRARY_NAME} voqc)
target_link_libraries(${LIBRARY_NAME} PUBLIC xacc::xacc xacc::quantum_gate ${XACC_DIR}/lib/libvoqc.so)
set_target_properties(${LIBRARY_NAME} PROPERTIES LINK_FLAGS "-shared")
set_target_properties(${LIBRARY_NAME} PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")
xacc_configure_plugin_rpath(${LIBRARY_NAME})
set (CMAKE_INSTALL_PREFIX "${XACC_DIR}" CACHE PATH "default install path" FORCE)
install(FILES $<TARGET_FILE:${LIBRARY_NAME}> DESTINATION ${CMAKE_INSTALL_PREFIX}/plugins) 

add_subdirectory(tests)
