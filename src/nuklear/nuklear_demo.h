#ifndef NUKLEAR_H_FILE
#define NUKLEAR_H_FILE

#ifndef __EMSCRIPTEN__
  #include "glad/glad.h"
#else
  #include "GLES3/gl3.h"
  // #include <emscripten.h>
#endif
#include "SDL3/SDL.h"
#include "SDL3/SDL_opengl.h"

#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#include "nuklear.h"
#include "nuklear_sdl_gl3.h"

extern int run(void);

#endif
