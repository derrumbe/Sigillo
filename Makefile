# Convenience targets for the C2PA Camera app.
#
#   make certs     - generate the test ES256 signing certificate + key
#   make project   - generate C2PACamera.xcodeproj via XcodeGen
#   make bootstrap  - certs + project (run this first)
#   make open      - open the generated project in Xcode
#   make clean     - remove generated project + bundled credentials

.PHONY: bootstrap certs project open clean

bootstrap: certs project

certs:
	@bash scripts/make_test_certs.sh

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
