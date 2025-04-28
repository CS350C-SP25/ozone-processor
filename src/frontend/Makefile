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

FRONTEND_VFLAGS = $(VFLAGS) --top-module frontend_tb
FRONTEND_SRCS = --cc ./frontend_tb.sv ./frontend.sv ./fetch.sv ./decode.sv ./branch_pred.sv ./cache/l0_instr_cache.sv ./cache/l1_instr_cache.sv \
				--cc  ../util/uop_pkg.sv ../util/stack.sv ../util/op_pkg.sv
FRONTEND_BIN = obj_dir/Vfrontend_tb

front: $(FRONTEND_BIN)


$(FRONTEND_BIN):
	$(VERILATOR) $(FRONTEND_VFLAGS) $(FRONTEND_SRCS)

decode:
	$(VERILATOR) $(VFLAGS) --cc ./decode.sv 

fetch:
	$(VERILATOR) $(VFLAGS) --cc ./fetch.sv

bp:
	$(VERILATOR) $(VFLAGS) --cc ./branch_pred.sv

frontend:
	$(VERILATOR) $(VFLAGS) --cc ./frontend.sv