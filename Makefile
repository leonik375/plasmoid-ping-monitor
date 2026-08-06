# Builds plasma-ping-helper, the small ICMP helper the plasmoid calls instead
# of /usr/bin/ping. The widget itself is plain QML and needs no build step.
#
#   make            build the helper
#   make install    install the helper into $(PREFIX)/bin
#   make check      build and run against a known good host
#   make dist       release tarball, complete unlike a GitHub source archive
#   make plasmoid   .plasmoid file to upload to store.kde.org

PREFIX  ?= $(HOME)/.local
CXX     ?= g++
CXXFLAGS ?= -O2 -std=c++11 -Wall -Wextra

BUILD   := build
LIB     := third_party/cpp-icmplib
BIN     := $(BUILD)/plasma-ping-helper

VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo unknown)
DIST    := plasmoid-ping-monitor-$(VERSION)

.PHONY: all install uninstall check check-version dist plasmoid clean

all: $(BIN)

$(LIB)/icmplib.h:
	@echo "The cpp-icmplib submodule is missing. Run:"
	@echo "    git submodule update --init --recursive"
	@false

# cpp-icmplib opens a raw socket, which needs CAP_NET_RAW, and falls back to an
# unprivileged Linux ping socket when that is refused. The submodule tracks the
# fork carrying that fallback until it is merged upstream, so no privileges are
# required here.
$(BIN): src/plasma-ping-helper.cpp $(LIB)/icmplib.h
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(LIB) -o $@ $<

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

# GitHub builds its source archives with git archive, which leaves submodule
# directories empty, so neither the download button nor the files generated for
# a release can be built from. This produces a complete tarball to attach to the
# release instead, and refuses rather than shipping one with the library missing.
# Plasma and store.kde.org decide whether an update exists from the version in
# metadata.json, so a release whose name disagrees with it would never reach
# anyone already running the widget. Keep the two from drifting.
check-version:
	@meta=$$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package/metadata.json); \
	 name=$$(echo "$(VERSION)" | sed 's/^v//'); \
	 case "$(VERSION)" in \
	   v[0-9]*) if [ "$$meta" != "$$name" ]; then \
	                echo "version mismatch: metadata.json says $$meta, tag says $$name"; \
	                echo "update package/metadata.json or move the tag"; exit 1; \
	            fi; \
	            echo "version $$meta" ;; \
	   *) echo "warning: $(VERSION) is not a release tag, metadata.json says $$meta" ;; \
	 esac

dist: check-version $(LIB)/icmplib.h
	@git diff --quiet HEAD || echo "warning: uncommitted changes will be included"
	@mkdir -p $(BUILD)
	@git ls-files --recurse-submodules > $(BUILD)/dist-files
	@grep -qx '$(LIB)/icmplib.h' $(BUILD)/dist-files \
	    || { echo "submodule contents are missing, run git submodule update --init"; false; }
	@tar czf $(DIST).tar.gz --transform 's,^,$(DIST)/,' -T $(BUILD)/dist-files
	@echo "created $(DIST).tar.gz  ($$(du -h $(DIST).tar.gz | cut -f1), $$(wc -l < $(BUILD)/dist-files) files)"

# The file store.kde.org distributes and Get New Widgets installs. It is the QML
# package alone: the helper cannot be delivered this way, so a widget installed
# from the store runs on /usr/bin/ping until the helper is built separately.
plasmoid: check-version
	@rm -f $(DIST).plasmoid
	@cd package && zip -qr $(CURDIR)/$(DIST).plasmoid . -x '.*' '*/.*'
	@echo "created $(DIST).plasmoid  ($$(du -h $(DIST).plasmoid | cut -f1))"

clean:
	rm -rf $(BUILD)
