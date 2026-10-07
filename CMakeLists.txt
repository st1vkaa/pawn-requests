cmake_minimum_required(VERSION 3.19)
project(sscanf LANGUAGES C CXX VERSION 2.15.1)

set(CMAKE_CXX_STANDARD 17)

include_directories(
	robin-hood-hashing/src/include
	string-view-lite/include
	open.mp/include
	span-lite/include
	glm
	amx
	.
)

add_definitions(
	-DPROJECT_NAME="sscanf"
	-DHAVE_STDINT_H=1
	-DGLM_FORCE_SSE2=1
	-DGLM_FORCE_QUAT_DATA_WXYZ=1
	-DNOMINMAX=1
	-Dnssv_CONFIG_SELECT_STRING_VIEW=nssv_STRING_VIEW_NONSTD
	-Dspan_CONFIG_SELECT_SPAN=span_SPAN_NONSTD
	-DPAWN_CELL_SIZE=32
)

if(MSVC)
	add_definitions(
		-DWIN32
		-D_CRT_SECURE_NO_DEPRECATE=1
		-DWIN32_LEAN_AND_MEAN=1
		-DSUBHOOK_STATIC
	)

	add_library(${PROJECT_NAME} SHARED
		amx/amx.c
		amx/amxplugin.c
		sscanf.def
		subhook/subhook.c
		array.cpp
		data.cpp
		enum.cpp
		kustom.cpp
		specifiers.cpp
		sscanf.cpp
		utils.cpp
		error.cpp
	)
elseif(UNIX)
	add_definitions(
		-DLINUX=1
	)

	set(CMAKE_C_FLAGS "-m32 -fPIC -O2 -w")
	set(CMAKE_CXX_FLAGS "-m32 -fPIC -O2 -w")

	add_library(${PROJECT_NAME} SHARED
		amx/amx.c
		amx/amxplugin.c
		amx/getch.c
		subhook/subhook.c
		array.cpp
		data.cpp
		enum.cpp
		kustom.cpp
		specifiers.cpp
		sscanf.cpp
		utils.cpp
		error.cpp
	)

	target_link_libraries(${PROJECT_NAME} dl)
endif()

set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT sscanf)

