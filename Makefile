VERSION := $(shell grep -m1 'MARKETING_VERSION = ' Sleepnot.xcodeproj/project.pbxproj | sed 's/.*MARKETING_VERSION = //;s/;.*//')
APP = build/Release/SLEEPNOT.app
ZIP = SLEEPNOT-$(VERSION).zip
DMG = SLEEPNOT-$(VERSION).dmg

.PHONY: build zip dmg verify clean

build:
	xcodebuild -project Sleepnot.xcodeproj -target Sleepnot -configuration Release build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64"

zip: build
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	shasum -a 256 $(ZIP)

dmg: build
	rm -f $(DMG)
	rm -rf /tmp/sleepnot-dmg && mkdir -p /tmp/sleepnot-dmg
	ditto $(APP) /tmp/sleepnot-dmg/SLEEPNOT.app
	ln -s /Applications /tmp/sleepnot-dmg/Applications
	hdiutil create -volname SLEEPNOT -srcfolder /tmp/sleepnot-dmg -ov -format UDZO $(DMG)
	shasum -a 256 $(DMG)

# Static guarantees: no display-sleep assertion, no Dock icon.
verify:
	@test -z "$$(grep -rn "idleDisplaySleepDisabled" Sleepnot/ || true)" || (echo "FAIL: must never block display sleep" && exit 1)
	@plutil -p $(APP)/Contents/Info.plist | grep -q '"LSUIElement" => true' || (echo "FAIL: LSUIElement must be true (run make build first)" && exit 1)
	@echo "OK: verify passed (version $(VERSION))"

clean:
	rm -rf build $(ZIP) $(DMG)
