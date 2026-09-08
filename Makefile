APP_NAME := Folio
APP := build/$(APP_NAME).app
DEST := /Applications/$(APP_NAME).app

.PHONY: build run test app open install release clean ios-project ios-build ios-test ios-run

build: ## Compile the SwiftPM target
	swift build

run: ## Run straight from SwiftPM (dev loop)
	swift run

test: ## Run the test suite
	swift test

app: ## Package build/Folio.app with the bundle id
	./scripts/package-app.sh release

open: app ## Package then launch the .app
	open "$(APP)"

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

install: app ## Build, package, and install to /Applications
	@pkill -9 -x Folio 2>/dev/null || true
	@pkill -9 -f "$(APP_NAME).app" 2>/dev/null || true
	@rm -rf "$(DEST)"
	@ditto "$(APP)" "$(DEST)"
	@rm -rf "$(APP)"
	@"$(LSREGISTER)" -f "$(DEST)" 2>/dev/null || true
	@echo "✓ installed → $(DEST)"

# --- iOS (simulator) -------------------------------------------------------
# The iOS app isn't a SwiftPM target: xcodegen writes FolioiOS.xcodeproj from
# project.yml. Override SIM to pick another simulator: make ios-test SIM="iPad Pro 13-inch (M4)"
SIM ?= iPhone 17 Pro
IOS_DEST := platform=iOS Simulator,name=$(SIM)
IOS_BUILD := xcodebuild -project FolioiOS.xcodeproj -scheme FolioiOS -destination '$(IOS_DEST)' -derivedDataPath build-ios

ios-project: ## Regenerate FolioiOS.xcodeproj from project.yml
	xcodegen generate

ios-build: ios-project ## Build the iOS app for the simulator
	$(IOS_BUILD) build

ios-test: ios-project ## Run the iOS unit + UI tests on the simulator
	$(IOS_BUILD) test

ios-run: ios-build ## Build, install, and launch the iOS app in the simulator
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(SIM)" build-ios/Build/Products/Debug-iphonesimulator/Folio.app
	xcrun simctl launch "$(SIM)" com.sriramb.folio

release: ## Build, sign, notarize, package, tag, and publish (make release VERSION=v0.1.0)
	@APP_NAME="$(APP_NAME)" VERSION="$(VERSION)" ./scripts/release.sh

clean: ## Remove build artifacts
	rm -rf .build build build-ios dist
