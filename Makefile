PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=

.PHONY: all build clean install

all: build

build:
	shards build

clean:
	rm -f bin/chess

install: build
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 bin/chess "$(DESTDIR)$(BINDIR)/chess"
