.PHONY: build test verify mac-app install secrets clean

build:
	swift build

test:
	swift test

secrets:
	./scripts/check-no-secrets.sh

verify: test secrets
	swift build

mac-app:
	./scripts/build-app.sh

install:
	./scripts/install.sh

clean:
	rm -rf .build dist
