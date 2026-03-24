PREFIX ?= /usr/local
BINARY = .build/release/dark-scripter
UNIVERSAL_BINARY = .build/apple/Products/Release/dark-scripter

build:
	swift build -c release --disable-sandbox

build-universal:
	swift build -c release --arch arm64 --arch x86_64 --disable-sandbox

package: build-universal
	cd .build/apple/Products/Release && zip dark-scripter-macos-universal.zip dark-scripter

install: build
	install -d $(PREFIX)/bin
	install $(BINARY) $(PREFIX)/bin/dark-scripter

uninstall:
	rm -f $(PREFIX)/bin/dark-scripter

clean:
	swift package clean

.PHONY: build build-universal package install uninstall clean
