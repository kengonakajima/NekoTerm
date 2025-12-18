.PHONY: build run release run-release clean

build:
	swift build

run: build
	.build/debug/NekoTerm

release:
	swift build -c release

run-release: release
	.build/release/NekoTerm

clean:
	swift package clean
