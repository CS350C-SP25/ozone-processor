ifneq ($(wildcard /u/nate/verilator),)
    VERILATOR := /u/nate/verilator
else
    VERILATOR := $(shell which verilator)
endif
$(info Using Verilator: $(VERILATOR))

CCACHE_PATH := $(shell which ccache 2>/dev/null)
ifeq ($(strip $(CCACHE_PATH)),)
    OBJCACHE :=
else
    OBJCACHE := OBJCACHE=ccache
endif
$(info OBJCACHE: $(OBJCACHE))

# Override VERILATOR if needed
VERILATOR ?= /u/nate/verilator

# Set flags based on OS
ifeq ($(shell uname),Linux)
	VFLAGS = --binary -j $$(( `nproc` - 1 )) --trace --trace-underscore --compiler clang --relative-includes
else
	VFLAGS = --binary -j $$(( `sysctl -n hw.logicalcpu` - 1 )) --trace --trace-underscore --compiler clang --relative-includes
endif

# Additional flags specific to our reg_file test bench
REGFILE_VFLAGS = $(VFLAGS) --top-module reg_file_tb

ifneq ($(wildcard /u/nate/verilator),)
    VERILATOR := /u/nate/verilator
else
    VERILATOR := $(shell which verilator)
endif
$(info Using Verilator: $(VERILATOR))

CCACHE_PATH := $(shell which ccache 2>/dev/null)
ifeq ($(strip $(CCACHE_PATH)),)
    OBJCACHE :=
else
    OBJCACHE := OBJCACHE=ccache
endif
$(info OBJCACHE: $(OBJCACHE))

# Override VERILATOR if needed
VERILATOR ?= /u/nate/verilator

# Set flags based on OS
ifeq ($(shell uname),Linux)
	VFLAGS = --binary -j $$(( `nproc` - 1 )) --trace --trace-underscore --compiler clang --relative-includes
else
	VFLAGS = --binary -j $$(( `sysctl -n hw.logicalcpu` - 1 )) --trace --trace-underscore --compiler clang --relative-includes
endif

# Additional flags specific to our reg_file test bench
REGFILE_VFLAGS = $(VFLAGS) --top-module reg_file_tb

# List the source files (adjust paths as needed)
REGFILE_SRCS = --cc ./reg_pkg.sv \
               --cc ./registers/reg_file.sv \
               --cc ./tb/reg_file_tb.sv \
               --exe obj_dir/Vreg_file_tb.cpp

# Name of the generated binary
REGFILE_BIN = obj_dir/Vreg_file_tb

# Rule to build the binary
$(REGFILE_BIN):
	$(VERILATOR) $(REGFILE_VFLAGS) $(REGFILE_SRCS)

# The regfile target runs the simulation
regfile: $(REGFILE_BIN)
	./$(REGFILE_BIN)

# Clean target
clean:
	rm -rf obj_dir

.PHONY: regfile clean