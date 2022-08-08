CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -Wpedantic -std=c11 -D_GNU_SOURCE
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

SHIM_SRC = src/pty_bridge.c src/ns_isolate.c src/cgroup_ctrl.c
SHIM_BIN = bin/conduit-shim

.PHONY: all build clean test test-unit test-integration test-regression benchmark install doctor

all: build

build:
	@mkdir -p bin
	@if command -v $(CC) >/dev/null 2>&1; then \
		echo "==> Compiling native accelerator shim with $(CC)..."; \
		$(CC) $(CFLAGS) -o $(SHIM_BIN) src/main.c $(SHIM_SRC) 2>/dev/null || \
		echo "==> Native shim compilation optional; falling back to pure Bash runtime."; \
	else \
		echo "==> C compiler not found; continuing in pure Bash mode."; \
	fi
	@chmod +x bin/conduit 2>/dev/null || true

test:
	@bash tests/run_tests.sh

test-unit:
	@bash tests/run_tests.sh --unit

test-integration:
	@bash tests/run_tests.sh --integration

test-regression:
	@bash tests/run_tests.sh --regression

benchmark:
	@bash tools/benchmark.sh

doctor:
	@bash bin/conduit doctor

clean:
	@rm -rf bin/conduit-shim build/ dist/ tests/tmp/ *.log *.pid
	@echo "==> Cleaned build and runtime artifacts."

install: build
	@mkdir -p $(DESTDIR)$(BINDIR)
	@cp -f bin/conduit $(DESTDIR)$(BINDIR)/conduit
	@if [ -f $(SHIM_BIN) ]; then cp -f $(SHIM_BIN) $(DESTDIR)$(BINDIR)/conduit-shim; fi
	@echo "==> Installed conduit to $(DESTDIR)$(BINDIR)"
