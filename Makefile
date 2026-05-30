# Convenience targets for the C2PA Camera app.
#
#   make certs     - generate the test ES256 signing certificate + key
#   make icon      - regenerate the app icon (requires Pillow)
#   make project   - generate C2PACamera.xcodeproj via XcodeGen
#   make bootstrap  - certs + project (run this first)
#   make open      - open the generated project in Xcode
#   make clean     - remove generated project + bundled credentials

.PHONY: bootstrap certs icon project open clean

bootstrap: certs project

certs:
	@bash scripts/make_test_certs.sh

icon:
	@python3 -c "import PIL" 2>/dev/null || { \
		echo "Pillow not found. Install it with: python3 -m pip install Pillow"; exit 1; }
	@python3 scripts/make_app_icon.py

project:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "XcodeGen not found. Install it with: brew install xcodegen"; exit 1; }
	@xcodegen generate
	@echo "Generated C2PACamera.xcodeproj"

open:
	@open C2PACamera.xcodeproj

clean:
	@rm -rf C2PACamera.xcodeproj
	@rm -f Sources/Resources/es256_certs.pem Sources/Resources/es256_private.key
