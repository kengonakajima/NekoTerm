.PHONY: build run release run-release clean app sign

build:
	swift build

run: build
	.build/debug/Nekotty

release:
	swift build -c release

run-release: release
	.build/release/Nekotty

clean:
	swift package clean
	rm -rf dist

app: release
	@echo "Creating app bundle..."
	@rm -rf dist/Nekotty.app
	@mkdir -p dist/Nekotty.app/Contents/MacOS
	@mkdir -p dist/Nekotty.app/Contents/Resources
	@cp .build/release/Nekotty dist/Nekotty.app/Contents/MacOS/
	@cp scripts/Info.plist dist/Nekotty.app/Contents/
	@cp scripts/AppIcon.icns dist/Nekotty.app/Contents/Resources/
	@echo "App bundle created: dist/Nekotty.app"

sign: app
	./sign.sh
