
ifeq ($(shell uname),Linux)
    NPROC := $(shell nproc)
else
    NPROC := $(shell sysctl -n hw.logicalcpu)
endif


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

OPTFLAGS := "-O0 -g0"

# Set flags based on OS
ifeq ($(shell uname),Linux)
	# VFLAGS = --binary -j $$(( `nproc` - 1 ))  --compiler clang --relative-includes
    VFLAGS = --binary -j $$(( `nproc` - 1 )) --compiler clang --relative-includes

else
	# VFLAGS = --binary -j $$(( `sysctl -n hw.logicalcpu` - 1 ))  --compiler clang --relative-includes
    VFLAGS = --binary -j 15  --compiler clang --relative-includes -fno-inline\
    --threads $(NPROC) --output-split 10000 -MMD -CFLAGS $(OPTFLAGS) --sv --language 1800-2012 --timing -Wno-lint

endif

FRONTEND_VFLAGS = $(VFLAGS) --top-module frontend_tb
FRONTEND_SRCS = --cc ./frontend_tb.sv ./frontend.sv ./fetch.sv ./decode.sv ./branch_pred.sv ./cache/l0_instr_cache.sv ./cache/l1_instr_cache.sv \
				--cc  ../util/uop_pkg.sv ../util/stackk.sv ../util/op_pkg.sv ../../mem/src/cache.sv #./cache/cache.sv 
FRONTEND_BIN = obj_dir/Vfrontend_tb

front: $(FRONTEND_BIN)
	./$(FRONTEND_BIN)

$(FRONTEND_BIN): verilate
	make -C obj_dir -f Vfrontend_tb.mk
verilate:
	$(VERILATOR) $(FRONTEND_VFLAGS) $(FRONTEND_SRCS)

-include $(wildcard obj_dir/*.d)


.PHONY: front verilate clean

clean:
	rm -rf obj_dir