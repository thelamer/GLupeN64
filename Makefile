DEBUG=0
PERF_TEST=0
HAVE_SHARED_CONTEXT=0
FORCE_GLES=0
FORCE_GLES3=0
HAVE_OPENGL=1

DYNAFLAGS :=
INCFLAGS  :=
COREFLAGS :=
CPUFLAGS  :=
GLFLAGS   :=

UNAME=$(shell uname -a)

# Dirs
ROOT_DIR := .
LIBRETRO_DIR := $(ROOT_DIR)/libretro

ifeq ($(platform),)
   platform = linux
   ifeq ($(UNAME),)
      platform = win
   else ifneq ($(findstring MINGW,$(UNAME)),)
      platform = win
   else ifneq ($(findstring Darwin,$(UNAME)),)
      platform = osx
   else ifneq ($(findstring win,$(UNAME)),)
      platform = win
   endif
else ifneq (,$(findstring armv,$(platform)))
   override platform += linux
else ifneq (,$(findstring rpi,$(platform)))
   override platform += linux
else ifneq (,$(findstring odroid,$(platform)))
   override platform += linux
endif

# system platform
system_platform = linux
ifeq ($(shell uname -a),)
   EXE_EXT = .exe
   system_platform = win
else ifneq ($(findstring Darwin,$(shell uname -a)),)
   system_platform = osx
   arch = intel
ifeq ($(shell uname -p),powerpc)
   arch = ppc
endif
else ifneq ($(findstring MINGW,$(shell uname -a)),)
   system_platform = win
endif

# Cross compile ?

ifeq (,$(ARCH))
   ARCH = $(shell uname -m)
endif

# Target Dynarec
WITH_DYNAREC = $(ARCH)

PIC = 1
ifeq ($(ARCH), $(filter $(ARCH), i386 i686))
   WITH_DYNAREC = x86
   PIC = 0
else ifeq ($(ARCH), $(filter $(ARCH), arm))
   WITH_DYNAREC = arm
endif

TARGET_NAME := glupen64
CC_AS ?= $(CC)

# Linux
ifneq (,$(findstring linux,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined
   
   ifeq ($(FORCE_GLES),1)
      GLES = 1
      GL_LIB := -lGLESv2
   else ifeq ($(FORCE_GLES3),1)
      GLES3 = 1
      GL_LIB := -lGLESv2
   else
      GL_LIB := -lGL
   endif
   
   # Raspberry Pi
   ifneq (,$(findstring rpi,$(platform)))
      GLES = 1
      GL_LIB := -L/opt/vc/lib -lGLESv2
      INCFLAGS += -I/opt/vc/include
      WITH_DYNAREC=arm
      ifneq (,$(findstring rpi2,$(platform)))
         CPUFLAGS += -DARM_ASM -DVC -DUSE_DEPTH_RENDERBUFFER
         CPUFLAGS += -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -mno-unaligned-access
         HAVE_NEON = 1
      else ifneq (,$(findstring rpi3,$(platform)))
         CPUFLAGS += -DARM_ASM -DVC -DUSE_DEPTH_RENDERBUFFER
         CPUFLAGS += -mcpu=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard -mno-unaligned-access
         HAVE_NEON = 1
      endif
      ifneq (,$(findstring cross,$(platform)))
         INCFLAGS += -I$(ROOT_DIR)/custom/rpi-cross
         GL_LIB += -L$(ROOT_DIR)/custom/rpi-cross -lrt
         CC = arm-linux-gnueabihf-gcc
         CXX = arm-linux-gnueabihf-g++
      endif
   endif
   
   # ODROIDs
   ifneq (,$(findstring odroid,$(platform)))
      BOARD := $(shell cat /proc/cpuinfo | grep -i odroid | awk '{print $$3}')
      GLES = 1
      GL_LIB := -lGLESv2
      CPUFLAGS += -DNO_ASM -DARM -D__arm__ -DARM_ASM -D__NEON_OPT -DNOSSE
      CPUFLAGS += -marm -mfloat-abi=hard -mfpu=neon
      HAVE_NEON = 1
      WITH_DYNAREC=arm
      ifneq (,$(findstring ODROIDC,$(BOARD)))
         # ODROID-C1
         CPUFLAGS += -mcpu=cortex-a5
      else ifneq (,$(findstring ODROID-XU3,$(BOARD)))
         # ODROID-XU3 & -XU3 Lite
         ifeq "$(shell expr `gcc -dumpversion` \>= 4.9)" "1"
            CPUFLAGS += -march=armv7ve -mcpu=cortex-a15.cortex-a7
         else
            CPUFLAGS += -mcpu=cortex-a9
         endif
      else
         # ODROID-U2, -U3, -X & -X2
         CPUFLAGS += -mcpu=cortex-a9
      endif
   endif
   
   # Generic ARM
   ifneq (,$(findstring armv,$(platform)))
      CPUFLAGS += -DNO_ASM -DARM -D__arm__ -DARM_ASM -DNOSSE
      WITH_DYNAREC=arm
      ifneq (,$(findstring neon,$(platform)))
         CPUFLAGS += -D__NEON_OPT -mfpu=neon
         HAVE_NEON = 1
      endif
   endif
   
   PLATFORM_EXT := linux

# i.MX6
else ifneq (,$(findstring imx6,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T
   GLES = 1
   GL_LIB := -lGLESv2
   CPUFLAGS += -DNO_ASM
   PLATFORM_EXT := linux
   WITH_DYNAREC=arm
   HAVE_NEON=1

# OS X
else ifneq (,$(findstring osx,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.dylib
   LDFLAGS += -dynamiclib
   OSXVER = `sw_vers -productVersion | cut -d. -f 2`
   OSX_LT_MAVERICKS = `(( $(OSXVER) <= 9)) && echo "YES"`
        LDFLAGS += -mmacosx-version-min=10.7
   LDFLAGS += -stdlib=libc++

   PLATCFLAGS += -D__MACOSX__ -DOSX
   GL_LIB := -framework OpenGL
   PLATFORM_EXT := linux

   # Target Dynarec
   ifeq ($(ARCH), $(filter $(ARCH), ppc))
      WITH_DYNAREC =
   endif

# iOS
else ifneq (,$(findstring ios,$(platform)))
   ifeq ($(IOSSDK),)
      IOSSDK := $(shell xcodebuild -version -sdk iphoneos Path)
   endif

   TARGET := $(TARGET_NAME)_libretro_ios.dylib
   DEFINES += -DIOS
   GLES = 1
   WITH_DYNAREC=arm
   PLATFORM_EXT := linux

   PLATCFLAGS += -DHAVE_POSIX_MEMALIGN -DNO_ASM
   PLATCFLAGS += -DIOS -marm
   CPUFLAGS += -DNO_ASM  -DARM -D__arm__ -DARM_ASM -D__NEON_OPT
   CPUFLAGS += -marm -mcpu=cortex-a8 -mfpu=neon -mfloat-abi=softfp
   LDFLAGS += -dynamiclib
   HAVE_NEON=1

   GL_LIB := -framework OpenGLES

   CC = clang -arch armv7 -isysroot $(IOSSDK)
   CC_AS = perl ./tools/gas-preprocessor.pl $(CC)
   CXX = clang++ -arch armv7 -isysroot $(IOSSDK)
   ifeq ($(platform),ios9)
      CC         += -miphoneos-version-min=8.0
      CC_AS      += -miphoneos-version-min=8.0
      CXX        += -miphoneos-version-min=8.0
      PLATCFLAGS += -miphoneos-version-min=8.0
   else
      CC += -miphoneos-version-min=5.0
      CC_AS += -miphoneos-version-min=5.0
      CXX += -miphoneos-version-min=5.0
      PLATCFLAGS += -miphoneos-version-min=5.0
   endif

# Theos iOS
else ifneq (,$(findstring theos_ios,$(platform)))
   DEPLOYMENT_IOSVERSION = 5.0
   TARGET = iphone:latest:$(DEPLOYMENT_IOSVERSION)
   ARCHS = armv7
   TARGET_IPHONEOS_DEPLOYMENT_VERSION=$(DEPLOYMENT_IOSVERSION)
   THEOS_BUILD_DIR := objs
   include $(THEOS)/makefiles/common.mk

   LIBRARY_NAME = $(TARGET_NAME)_libretro_ios
   DEFINES += -DIOS
   GLES = 1
   WITH_DYNAREC=arm

   PLATCFLAGS += -DHAVE_POSIX_MEMALIGN -DNO_ASM
   PLATCFLAGS += -DIOS -marm
   CPUFLAGS += -DNO_ASM  -DARM -D__arm__ -DARM_ASM -D__NEON_OPT -DNOSSE
   HAVE_NEON=1


# Android
else ifneq (,$(findstring android,$(platform)))
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined -Wl,--warn-common -march=armv7-a -Wl,--fix-cortex-a8
   LDFLAGS += -llog
   ifneq (,$(findstring gles3,$(platform)))
   GL_LIB := -lGLESv3
   GLES3 = 1
   TARGET := $(TARGET_NAME)_libretro_android_gles3.so
   else
   GL_LIB := -lGLESv2
   GLES = 1
   TARGET := $(TARGET_NAME)_libretro_android.so
   endif
   CC = arm-linux-androideabi-gcc
   CXX = arm-linux-androideabi-g++
   WITH_DYNAREC=arm
   HAVE_NEON = 1
   CPUFLAGS += -march=armv7-a -mfloat-abi=softfp -mfpu=neon -DARM_ASM -DANDROID -mno-unaligned-access

   PLATFORM_EXT := linux

# QNX
else ifeq ($(platform), qnx)
   TARGET := $(TARGET_NAME)_libretro_qnx.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined -Wl,--warn-common
   GL_LIB := -lGLESv2

   CC = qcc -Vgcc_ntoarmv7le
   CC_AS = qcc -Vgcc_ntoarmv7le
   CXX = QCC -Vgcc_ntoarmv7le
   AR = QCC -Vgcc_ntoarmv7le
   WITH_DYNAREC=arm
   GLES = 1
   PLATCFLAGS += -DNO_ASM -D__BLACKBERRY_QNX__
   CPUFLAGS += -DNOSSE
   HAVE_NEON = 1
   CPUFLAGS += -marm -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp -D__arm__ -DARM_ASM -D__NEON_OPT -DNOSSE
   CFLAGS += -D__QNX__

   PLATFORM_EXT := linux

# emscripten
else ifeq ($(platform), emscripten)
   TARGET := $(TARGET_NAME)_libretro_emscripten.bc
   GLES := 1
   WITH_DYNAREC :=
   CPUFLAGS += -Dasm=asmerror -D__asm__=asmerror -DNO_ASM -DNOSSE
   SINGLE_THREAD := 1
   PLATCFLAGS += -Dmain_exit=mupen_main_exit \
                 -Drglgen_resolve_symbols_custom=mupen_rglgen_resolve_symbols_custom \
                 -Drglgen_resolve_symbols=mupen_rglgen_resolve_symbols \
                 -Dsinc_resampler=mupen_sinc_resampler \
                 -Dnearest_resampler=mupen_nearest_resampler \
                 -DCC_resampler=mupen_CC_resampler \
                 -Daudio_resampler_driver_find_handle=mupen_audio_resampler_driver_find_handle \
                 -Daudio_resampler_driver_find_ident=mupen_audio_resampler_driver_find_ident \
                 -Drarch_resampler_realloc=mupen_rarch_resampler_realloc 
   HAVE_NEON = 0
   PLATFORM_EXT := linux
   CFLAGS += -s ASYNCIFY
   LDFLAGS += -s TOTAL_MEMORY=33554432 -s ASYNCIFY
   SOURCES_C += $(CORE_DIR)/src/r4300/empty_dynarec.c
   #HAVE_SHARED_CONTEXT := 1

# Windows
else ifneq (,$(findstring win,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.dll
   LDFLAGS += -shared -static-libgcc -static-libstdc++ -Wl,--version-script=$(LIBRETRO_DIR)/link.T -lwinmm -lgdi32
   GL_LIB := -lopengl32
   PLATFORM_EXT := win32
   CC = x86_64-w64-mingw32-gcc
   CXX = x86_64-w64-mingw32-g++
endif

ifneq (,$(findstring win,$(platform)))
   COREFLAGS += -DOS_WINDOWS -DMINGW
   ASFLAGS = -f win32
else
   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
endif

include Makefile.common

ifeq ($(HAVE_NEON), 1)
   COREFLAGS += -DHAVE_NEON -D__ARM_NEON__ -D__NEON_OPT
endif

ifeq ($(PERF_TEST), 1)
   COREFLAGS += -DPERF_TEST
endif

ifeq ($(HAVE_SHARED_CONTEXT), 1)
   COREFLAGS += -DHAVE_SHARED_CONTEXT
endif

ifeq ($(SINGLE_THREAD), 1)
   COREFLAGS += -DSINGLE_THREAD
endif

COREFLAGS += -D__LIBRETRO__ -DM64P_PLUGIN_API -DM64P_CORE_PROTOTYPES -D_ENDUSER_RELEASE -DSINC_LOWER_QUALITY -DMUPENPLUSAPI -DTXFILTER_LIB -D__VEC4_OPT


ifeq ($(DEBUG), 1)
   CPUOPTS += -O0 -g
   CPUOPTS += -DOPENGL_DEBUG
else
   CPUOPTS += -O3 -DNDEBUG
endif

#ifeq ($(platform), qnx)
#   CFLAGS   += -Wp,-MMD
#   CXXFLAGS += -Wp,-MMD
#else
#   CFLAGS   += -std=gnu89 -MMD
#endif
CXXFLAGS += -std=c++11
### Finalize ###
ifeq ($(PIC), 1)
   fpic = -fPIC
else
   fpic = -fno-PIC
endif

OBJECTS     += $(SOURCES_CXX:.cpp=.o) $(SOURCES_C:.c=.o) $(SOURCES_ASM:.S=.o) $(SOURCES_NASM:.asm=.o)
CXXFLAGS    += $(CPUOPTS) $(COREFLAGS) $(INCFLAGS) $(PLATCFLAGS) $(fpic) $(PLATCFLAGS) $(CPUFLAGS) $(GLFLAGS) $(DYNAFLAGS)
CFLAGS      += $(CPUOPTS) $(COREFLAGS) $(INCFLAGS) $(PLATCFLAGS) $(fpic) $(PLATCFLAGS) $(CPUFLAGS) $(GLFLAGS) $(DYNAFLAGS)

ifeq ($(findstring Haiku,$(UNAME)),)
   LDFLAGS += -lm
endif

LDFLAGS    += $(fpic) -lz

ifeq ($(platform), theos_ios)
COMMON_FLAGS := -DIOS $(COMMON_DEFINES) $(INCFLAGS) -I$(THEOS_INCLUDE_PATH) -Wno-error
$(LIBRARY_NAME)_ASFLAGS += $(CFLAGS) $(COMMON_FLAGS)
$(LIBRARY_NAME)_CFLAGS += $(CFLAGS) $(COMMON_FLAGS)
$(LIBRARY_NAME)_CXXFLAGS += $(CXXFLAGS) $(COMMON_FLAGS)
${LIBRARY_NAME}_FILES = $(SOURCES_CXX) $(SOURCES_C) $(SOURCES_ASM) $(SOURCES_NASM)
${LIBRARY_NAME}_FRAMEWORKS = OpenGLES
${LIBRARY_NAME}_LIBRARIES = z
include $(THEOS_MAKE_PATH)/library.mk
else
all: $(TARGET)
$(TARGET): $(OBJECTS)
	$(CXX) -o $@ $(OBJECTS) $(LDFLAGS) $(GL_LIB)

%.o: %.asm
	nasm $(ASFLAGS) $< -o $@

%.o: %.S
	$(CC_AS) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@


clean:
	find -name "*.o" -type f -delete
	find -name "*.d" -type f -delete
	rm -f $(TARGET)

.PHONY: clean
-include $(OBJECTS:.o=.d)
endif
