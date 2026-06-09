# Convenience targets for the Sigillo app.
#
#   make certs     - generate the test ES256 signing certificate + key
#   make icon      - regenerate the app icon (requires Pillow)
#   make project   - generate Sigillo.xcodeproj via XcodeGen
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
	@echo "Generated Sigillo.xcodeproj"

open:
	@open Sigillo.xcodeproj

clean:
	@rm -rf Sigillo.xcodeproj
	@rm -f Sources/Resources/es256_certs.pem Sources/Resources/es256_private.key
