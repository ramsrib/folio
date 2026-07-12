APP_NAME := Folio
APP := build/$(APP_NAME).app
DEST := /Applications/$(APP_NAME).app

.PHONY: build run app open install release clean

build: ## Compile the SwiftPM target
	swift build

run: ## Run straight from SwiftPM (dev loop)
	swift run

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

release: ## Build, sign, notarize, package, tag, and publish (make release VERSION=v0.1.0)
	@APP_NAME="$(APP_NAME)" VERSION="$(VERSION)" ./scripts/release.sh

clean: ## Remove build artifacts
	rm -rf .build build dist
