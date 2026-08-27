# Endless Frontier — the commands that are not in Xcode.
#
# The Core suite is the long one (1604 tests, ~18 minutes): batch the edits and
# run it ONCE, at the end, or narrow it with `make test-filter F=Siege`.
# `make verify-docs` needs neither Xcode nor the network — run it before every
# commit.

APP_PROJECT := App/EndlessFrontier.xcodeproj
SCHEME      := EndlessFrontier
# The only iPhone runtime installed on this host. The name goes stale with
# Xcode; check with `make simulators` before believing a destination error.
SIM         := platform=iOS Simulator,name=iPhone 17
DEST        ?= $(SIM)
F           ?=

.PHONY: help test test-filter generate build test-app verify-docs check simulators

help:
	@echo "make test         the Core suite — deterministic, no simulator (~18 min)"
	@echo "make test-filter  one suite: make test-filter F=Siege"
	@echo "make generate     regenerate the Xcode project from App/project.yml"
	@echo "make build        build the iOS app for the simulator"
	@echo "make test-app     the App suite"
	@echo "make verify-docs  FMEA targets, links, rule numbering, engine index, content tables, Czech"
	@echo "make check        verify-docs + the Core suite"
	@echo "make simulators   what this host actually has installed"

test:
	cd Core && swift test

test-filter:
	@test -n "$(F)" || (echo "usage: make test-filter F=<suite substring>" && exit 1)
	cd Core && swift test --filter $(F)

generate:
	cd App && xcodegen generate

build:
	xcodebuild build -project $(APP_PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -quiet

test-app:
	xcodebuild test -project $(APP_PROJECT) -scheme $(SCHEME) -destination '$(DEST)' 2>&1 \
		| tee /tmp/endless-frontier-test.log \
		| grep -E "^(Test Suite|Test Case).*(passed|failed)" || true
	@echo "--- failures ---"
	@grep "' failed (" /tmp/endless-frontier-test.log || echo "none"

verify-docs:
	@python3 scripts/verify-docs.py

check: verify-docs test

simulators:
	xcrun simctl list devices available | grep iPhone
