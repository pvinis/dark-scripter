PREFIX ?= /usr/local

build:
	swift build -c release --disable-sandbox

install: build
	install -d $(PREFIX)/bin
	install .build/release/dark-scripter $(PREFIX)/bin/dark-scripter

uninstall:
	rm -f $(PREFIX)/bin/dark-scripter

clean:
	swift package clean

.PHONY: build install uninstall clean
