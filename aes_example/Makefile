# make          device image (.pdi)
# make sim      simulate AES_TOP at the pins
# make program  upload over JTAG
# make clean    remove all generated files

SHELL := /bin/bash

VIVADO_ON_PATH := $(shell command -v vivado 2>/dev/null)
ifeq ($(VIVADO_ON_PATH),)
VIVADO := $(lastword $(sort $(wildcard /opt/Xilinx/*/Vivado/bin/vivado)))
else
VIVADO := $(VIVADO_ON_PATH)
endif

XV      := $(dir $(VIVADO))
XVLOG   := $(XV)xvlog
XELAB   := $(XV)xelab
XSIM    := $(XV)xsim

TOP     := AES_TOP
BUILD   := build
IMAGE   := $(BUILD)/$(TOP).pdi

RTL_ORDERED := \
  uart_sv/rtl/UART_PKG.sv \
  uart_sv/rtl/UART_TX_IF.sv \
  uart_sv/rtl/UART_RX_IF.sv \
  uart_sv/rtl/UART_BAUD_GEN.sv \
  uart_sv/rtl/UART_MAJORITY.sv \
  uart_sv/rtl/UART_FIFO.sv \
  uart_sv/rtl/UART_TX.sv \
  uart_sv/rtl/UART_RX.sv \
  uart_sv/rtl/UART_CORE.sv \
  aes/rtl/core/AES_PKG.sv \
  $(filter-out aes/rtl/core/AES_PKG.sv,$(wildcard aes/rtl/core/*.sv)) \
  $(wildcard aes/rtl/keyschedule/*.sv) \
  rtl/AES_TOP.sv

SRC := $(wildcard rtl/*.sv) \
       $(wildcard uart_sv/rtl/*.sv) \
       $(wildcard aes/rtl/core/*.sv) \
       $(wildcard aes/rtl/keyschedule/*.sv) \
       CW308_XCSU.xdc \
       scripts/build.tcl

.PHONY: all sim program clean tools
all: tools $(IMAGE)

sim: tools
	@mkdir -p $(BUILD)/sim
	@cp -f aes/rtl/keyschedule/RCON.mem $(BUILD)/sim/
	@cd $(BUILD)/sim && \
	  $(XVLOG) -sv -i $(abspath test) $(addprefix $(abspath .)/,$(RTL_ORDERED)) $(abspath test)/AES_TOP_TB.sv > compile.log 2>&1 \
	    || { echo "COMPILE FAILED"; grep -E 'ERROR' compile.log | head -6; exit 1; }
	@cd $(BUILD)/sim && \
	  $(XELAB) -timescale 1ns/1ps AES_TOP_TB -s aes_top_tb > elab.log 2>&1 \
	    || { echo "ELAB FAILED"; grep -E 'ERROR' elab.log | head -6; exit 1; }
	@cd $(BUILD)/sim && $(XSIM) aes_top_tb -R 2>&1 | grep -E 'TEST PASSED|TEST FAILED|FAIL \[' || true

tools:
	@if [ -z "$(VIVADO)" ] || [ ! -x "$(VIVADO)" ]; then \
	  echo "vivado not found: put it on PATH or install under /opt/Xilinx/<ver>/Vivado"; exit 1; \
	fi
	@echo "using $(VIVADO)"

$(IMAGE): $(SRC)
	@mkdir -p $(BUILD)
	@cd $(BUILD) && $(VIVADO) -mode batch -nojournal -notrace \
	    -log build.log -source ../scripts/build.tcl \
	  | tee build.stdout | grep -E '^(BUILD_OK|BOOTGEN_FAIL|ERROR|CRITICAL WARNING)' || true
	@test -f $(IMAGE) || { echo "no device image produced - see $(BUILD)/build.log"; exit 1; }
	@grep -E '^BUILD_OK' $(BUILD)/build.stdout

program: tools
	@test -f $(IMAGE) || { echo "no device image: run make first"; exit 1; }
	@cd $(BUILD) && $(VIVADO) -mode batch -nojournal -notrace \
	    -log program.log -source ../scripts/program.tcl -tclargs $(TOP).pdi \
	  | grep -E '^(FOUND|DONE_STATUS|PROGRAM_OK|PROGRAM_FAIL|ERROR)' || true

clean:
	@rm -rf $(BUILD) .Xil vivado*.jou vivado*.log *.str
