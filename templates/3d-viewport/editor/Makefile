# editor/Makefile — godot-blockout
IMGUI ?= $(IMGUI_DIR)
LUA   ?= $(LUA_SRC)
STBI  ?= $(STB_INC)

BUILD := ../build
OBJ   := $(BUILD)/obj
OUT   := $(BUILD)/godot-blockout.exe

FONTS_H := $(BUILD)/fonts_embedded.h
FONT_UI  := ../assets/fonts/InterVariable.ttf
FONT_MONO := ../assets/fonts/JetBrainsMono-Regular.ttf

SRC := src/main.cpp src/app.cpp src/ig.cpp src/lua.cpp src/math3d.cpp

IMGUI_CORE := imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp
IMGUI_BACKEND := imgui_impl_sdl3.cpp imgui_impl_sdlrenderer3.cpp

LUA_C := $(filter-out $(LUA)/src/lua.c $(LUA)/src/luac.c,$(wildcard $(LUA)/src/*.c))

CXXFLAGS_COMMON := -std=c++17 -O2 -g -Wall -Wno-unknown-pragmas \
  -I src -I $(BUILD) -I $(IMGUI) -I $(IMGUI)/backends \
  -I $(LUA)/src -I $(STBI) -I $(STBI)/stb -I src/vendor/stb

OBJ_CXX := $(addprefix $(OBJ)/,$(notdir $(SRC:.cpp=.o)) \
             $(IMGUI_CORE:.cpp=.o) $(IMGUI_BACKEND:.cpp=.o))
OBJ_LUA := $(addprefix $(OBJ)/lua/,$(notdir $(LUA_C:.c=.o)))

# Windows (default)
WIN_CXX := $(MINGW_CXX)
WIN_CC   := $(MINGW_CC)

WIN_CXXFLAGS := $(CXXFLAGS_COMMON) -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE \
  -I $(SDL3_CROSS_INC)
WIN_LDFLAGS  := -static-libgcc -static-libstdc++ -mconsole
WIN_LIBS := -L$(SDL3_CROSS_LIB) -lSDL3 \
  -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic \
  -lgdi32 -limm32 -lole32 -loleaut32 -lversion -lwinmm -luuid -ldxgi -ld3d11 \
  -lsetupapi -lcomdlg32 -lshell32 -luser32 -lkernel32

win: $(OUT)
$(OUT): $(OBJ_CXX) $(OBJ_LUA) | $(BUILD)
	$(WIN_CXX) $(OBJ_CXX) $(OBJ_LUA) -o $(OUT) $(WIN_LDFLAGS) $(WIN_LIBS)
	@echo "built $(OUT)"

# Linux
LINUX_CXX := $(CXX)
SDL3_CFLAGS ?= $(shell pkg-config --cflags sdl3 2>/dev/null)
SDL3_LIBS   ?= $(shell pkg-config --libs sdl3 2>/dev/null)
, := ,
LIN_RPATH := $(patsubst -L%,-Wl$(,)-rpath$(,)%,$(filter -L%,$(SDL3_LIBS)))

LINUX_OUT := $(BUILD)/godot-blockout
LINUX_CXXFLAGS := $(CXXFLAGS_COMMON) $(SDL3_CFLAGS)
LINUX_LDFLAGS  := -static-libgcc -static-libstdc++
LINUX_LIBS := $(SDL3_LIBS) -lm -ldl -lpthread $(LIN_RPATH)

OBJL := $(BUILD)/obj-linux
OBJL_CXX := $(addprefix $(OBJL)/,$(notdir $(SRC:.cpp=.o)) \
              $(IMGUI_CORE:.cpp=.o) $(IMGUI_BACKEND:.cpp=.o))
OBJL_LUA := $(addprefix $(OBJL)/lua/,$(notdir $(LUA_C:.c=.o)))

linux: $(LINUX_OUT)
$(LINUX_OUT): $(OBJL_CXX) $(OBJL_LUA) | $(BUILD)
	$(LINUX_CXX) $(OBJL_CXX) $(OBJL_LUA) -o $(LINUX_OUT) $(LINUX_LDFLAGS) $(LINUX_LIBS)
	@echo "built $(LINUX_OUT)"

$(OBJ)/%.o: src/%.cpp src/editor.h | $(OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(OBJ)/%.o: $(IMGUI)/%.cpp | $(OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(OBJ)/%.o: $(IMGUI)/backends/%.cpp | $(OBJ)
	$(WIN_CXX) $(WIN_CXXFLAGS) -c $< -o $@
$(OBJ)/lua/%.o: $(LUA)/src/%.c | $(OBJ)/lua
	$(WIN_CC) -O2 -std=c11 -I $(LUA)/src -c $< -o $@

$(OBJL)/%.o: src/%.cpp src/editor.h | $(OBJL)
	$(LINUX_CXX) $(LINUX_CXXFLAGS) -c $< -o $@
$(OBJL)/%.o: $(IMGUI)/%.cpp | $(OBJL)
	$(LINUX_CXX) $(LINUX_CXXFLAGS) -c $< -o $@
$(OBJL)/%.o: $(IMGUI)/backends/%.cpp | $(OBJL)
	$(LINUX_CXX) $(LINUX_CXXFLAGS) -c $< -o $@
$(OBJL)/lua/%.o: $(LUA)/src/%.c | $(OBJL)/lua
	$(CC) -O2 -std=c11 -I $(LUA)/src -c $< -o $@

$(FONTS_H): ../tools/embed.py $(FONT_UI) $(FONT_MONO) | $(BUILD)
	python3 ../tools/embed.py $@ \
	  font_ui=$(FONT_UI) font_mono=$(FONT_MONO)

$(BUILD):
	mkdir -p $(BUILD)
$(OBJ):
	mkdir -p $(OBJ)
$(OBJ)/lua:
	mkdir -p $(OBJ)/lua
$(OBJL):
	mkdir -p $(OBJL)
$(OBJL)/lua:
	mkdir -p $(OBJL)/lua

shot: linux
	cd .. && SDL_VIDEODRIVER=offscreen ./build/godot-blockout --shot build/shot.png --frames 20

test: linux
	cd .. && ./build/godot-blockout --test

package: win
	mkdir -p $(BUILD)/godot-blockout-win64
	rm -f $(BUILD)/godot-blockout-win64/SDL3.dll $(BUILD)/godot-blockout-win64/libmcfgthread-2.dll
	cp $(OUT) $(BUILD)/godot-blockout-win64/
	cp $(SDL3_CROSS_DLL) $(BUILD)/godot-blockout-win64/
	cp $(MCFG_DLL) $(BUILD)/godot-blockout-win64/
	rm -rf $(BUILD)/godot-blockout-win64/lua
	cp -r ../editor/lua $(BUILD)/godot-blockout-win64/lua
	@echo "packaged $(BUILD)/godot-blockout-win64/"

clean:
	rm -rf $(OBJ) $(OBJL) $(BUILD)/godot-blockout-win64 $(OUT) $(LINUX_OUT)

.PHONY: win linux test shot package clean
