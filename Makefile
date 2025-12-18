.PHONY: build run clean

build:
	swift build -c release

run: build
	.build/release/NekoTerm

clean:
	swift package clean
