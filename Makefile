# Builds plasma-ping-helper, the small ICMP helper the plasmoid calls instead
# of /usr/bin/ping. The widget itself is plain QML and needs no build step.
#
#   make            build against unprivileged ping sockets (no root needed)
#   make RAW=1      build against raw sockets, needs CAP_NET_RAW (see README)
#   make install    install the helper into $(PREFIX)/bin
#   make check      build and run against a known good host

PREFIX  ?= $(HOME)/.local
CXX     ?= g++
CXXFLAGS ?= -O2 -std=c++11 -Wall -Wextra
RAW     ?= 0

BUILD   := build
LIB     := third_party/cpp-icmplib
PATCH   := patches/0001-unprivileged-ping-sockets.patch
BIN     := $(BUILD)/plasma-ping-helper

.PHONY: all install uninstall check clean

all: $(BIN)

$(LIB)/icmplib.h:
	@echo "The cpp-icmplib submodule is missing. Run:"
	@echo "    git submodule update --init --recursive"
	@false

# The library opens a raw socket, which would need CAP_NET_RAW on whatever
# runs it. The patch moves it onto Linux ping sockets so the helper works as
# an ordinary user. Upstream stays untouched in the submodule.
$(BUILD)/icmplib.h: $(LIB)/icmplib.h $(PATCH)
	@mkdir -p $(BUILD)
	cp $(LIB)/icmplib.h $@
ifeq ($(RAW),0)
	patch -s -p1 -d $(BUILD) -i $(CURDIR)/$(PATCH)
	@echo "built for unprivileged ping sockets"
else
	@echo "built for raw sockets: run 'sudo setcap cap_net_raw+ep $(BIN)' after make"
endif

$(BIN): src/plasma-ping-helper.cpp $(BUILD)/icmplib.h
	$(CXX) $(CXXFLAGS) -I$(BUILD) -o $@ $<

install: all
	install -Dm755 $(BIN) $(DESTDIR)$(PREFIX)/bin/plasma-ping-helper
	@echo "installed $(DESTDIR)$(PREFIX)/bin/plasma-ping-helper"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/plasma-ping-helper

check: all
	@echo "--- reachable host ---"; $(BIN) 1.1.1.1 -w 2000; \
	 echo "--- unroutable host ---"; $(BIN) 192.0.2.1 -w 1000; \
	 echo "--- bad name ---"; $(BIN) nonexistent.invalid; \
	 echo "(exit statuses above: 0 reply, 1 no reply, 2 error)"

clean:
	rm -rf $(BUILD)
