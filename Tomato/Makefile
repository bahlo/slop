.PHONY: build test smoke app clean

APP := dist/Tomato.app

# The Command Line Tools ship Testing.framework but SwiftPM does not add its
# search path automatically (no full Xcode installed), so pass it explicitly.
TOOLCHAIN_FRAMEWORKS := $(shell xcode-select -p)/Library/Developer/Frameworks
TOOLCHAIN_TESTLIBS := $(shell xcode-select -p)/Library/Developer/usr/lib
# The default (swift-build) build system also misses the TestingMacros plugin
# (@Test, #expect), which the CLT keep in a subdirectory of the plugin path.
TOOLCHAIN_TESTPLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TOOLCHAIN_TESTPLUGINS) \
	-Xswiftc -F$(TOOLCHAIN_FRAMEWORKS) \
	-Xlinker -F$(TOOLCHAIN_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TOOLCHAIN_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TOOLCHAIN_TESTLIBS)

build:
	swift build

test:
	swift test $(TEST_FLAGS)

smoke:
	scripts/smoke.sh

# Assemble an ad-hoc-signed app bundle from the SwiftPM release build.
# No Xcode required: Info.plist is checked in, the icon is rendered by a
# Swift script + iconutil (both ship with the Command Line Tools / macOS).
app:
	swift build -c release
	rm -rf $(APP) dist/AppIcon.iconset
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Tomato $(APP)/Contents/MacOS/
	cp -R .build/release/Tomato_Tomato.bundle $(APP)/Contents/Resources/
	cp Support/Info.plist $(APP)/Contents/
	swift scripts/make-icon.swift dist/AppIcon.iconset
	iconutil -c icns dist/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns
	rm -rf dist/AppIcon.iconset
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

clean:
	rm -rf .build dist
