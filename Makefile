PROJECT = Penumbra.xcodeproj
SCHEME  = Penumbra

BUILD_DIR := $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-configuration Release -showBuildSettings 2>/dev/null \
	| awk -F' = ' '/^ *BUILT_PRODUCTS_DIR =/{print $$2}')

.PHONY: build install clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

install: build
	cp -R "$(BUILD_DIR)/Penumbra.app" /Applications/
	xattr -dr com.apple.quarantine /Applications/Penumbra.app
	@echo "Installed to /Applications/Penumbra.app"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
