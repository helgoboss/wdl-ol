cmake_minimum_required(VERSION 3.10)
project(wdl)
option(WDL_EEL2 "Builds eel2" OFF)

if (WDL_EEL2)
  set(EEL2_SOURCES
      eel2/nseel-cfunc.c
      eel2/nseel-compiler.c
      eel2/nseel-caltab.c
      eel2/nseel-eval.c
      eel2/nseel-lextab.c
      eel2/nseel-ram.c
      eel2/nseel-yylex.c
      )
  add_library(wdl-eel2 ${EEL2_SOURCES})
  target_include_directories(wdl-eel2 INTERFACE .)
  if (MSVC)
    if (NOT ${MSVC_C_ARCHITECTURE_ID} MATCHES X86)
      target_link_libraries(wdl-eel2 eel2/asm-nseel-x64.obj)
    endif ()
  elseif (APPLE)
    target_link_libraries(wdl-eel2 eel2/asm-nseel-x64-macho.o)
  endif ()
endif ()