.PHONY: build run release run-release clean app sign

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
	rm -rf dist

app: release
	@echo "Creating app bundle..."
	@rm -rf dist/NekoTerm.app
	@mkdir -p dist/NekoTerm.app/Contents/MacOS
	@mkdir -p dist/NekoTerm.app/Contents/Resources
	@cp .build/release/NekoTerm dist/NekoTerm.app/Contents/MacOS/
	@cp scripts/Info.plist dist/NekoTerm.app/Contents/
	@cp scripts/AppIcon.icns dist/NekoTerm.app/Contents/Resources/
	@echo "App bundle created: dist/NekoTerm.app"

sign: app
	./sign.sh
