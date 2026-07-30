.PHONY: project open verify clean

project:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen first: brew install xcodegen" && exit 1)
	xcodegen generate

open: project
	open Luma.xcodeproj

verify:
	./Scripts/verify.sh

clean:
	rm -rf Luma.xcodeproj DerivedData .build

