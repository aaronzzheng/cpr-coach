# make dev | make sim | make test | make build
PY := backend/.venv/bin/python
SCENARIO ?= good

.PHONY: setup dev demo backend web sim record replay test lint build swift-check apple-project apple-signing apple-install apple-install-phone

setup:
	cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd web && npm install

# Runs uvicorn on 0.0.0.0:8000 and vite on 5173; Ctrl-C stops both.
dev:
	@trap 'kill 0' INT TERM EXIT; \
	(cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload) & \
	(cd web && npm run dev) & \
	wait

# Demo / judging: one stable process (no auto-reload) serving the built dashboard at :$(PORT).
PORT ?= 8000
demo: build
	@echo "CPR Coach → http://localhost:$(PORT)   (phone: ws://$$(ipconfig getifaddr en0 2>/dev/null || echo LAPTOP_IP):$(PORT)/ingest)"
	cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $(PORT) --log-level warning

backend:
	cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

web:
	cd web && npm run dev

sim:
	cd backend && .venv/bin/python -m tools.sim_watch --scenario $(SCENARIO)

# Record a golden session for backup replay. Real watch: make record NAME=good
# Simulator: make record NAME=fatigue SIM=fatigue DURATION=150
DURATION ?= 60
record:
	@test -n "$(NAME)" || (echo "usage: make record NAME=good [SIM=good DURATION=60]"; exit 1)
	cd backend && .venv/bin/python -m tools.record ../recordings/$(NAME).jsonl $(if $(SIM),--sim $(SIM) --duration $(DURATION),)

SPEED ?= 1
replay:
	@test -n "$(SESSION)" || (echo "usage: make replay SESSION=data/sessions/<id> [SPEED=2]"; exit 1)
	cd backend && .venv/bin/python -m tools.replay "$(abspath $(SESSION))" --speed $(SPEED)

test:
	cd backend && .venv/bin/pytest -q
	cd web && npm run typecheck && npm test

lint:
	cd backend && .venv/bin/ruff check app tests tools

build:
	cd web && npm run build

# Typecheck the Swift sources against the watchOS 10 / iOS 17 SDKs (no Xcode project needed).
swift-check:
	xcrun --sdk watchos swiftc -typecheck -parse-as-library -swift-version 6 -target arm64_32-apple-watchos10.0 $$(find apple/Sources/Watch -name '*.swift')
	xcrun --sdk iphoneos swiftc -typecheck -parse-as-library -swift-version 6 -target arm64-apple-ios17.0 $$(find apple/Sources/iOS -name '*.swift')
	@echo "Swift sources typecheck OK"

# Generate apple/CPRCoach.xcodeproj from apple/project.yml (brew install xcodegen).
apple-project:
	cd apple && xcodegen generate --spec project.yml

# Write your signing settings: make apple-signing TEAM=ABCDE12345 PREFIX=com.yourname
apple-signing:
	@test -n "$(TEAM)" -a -n "$(PREFIX)" || (echo "usage: make apple-signing TEAM=<team id> PREFIX=com.yourname"; exit 1)
	printf 'DEVELOPMENT_TEAM = $(TEAM)\nBUNDLE_ID_PREFIX = $(PREFIX)\n' > apple/Config/Local.xcconfig
	@echo "wrote apple/Config/Local.xcconfig"

# Build, sign and install the iPhone relay (with the watch app inside) on a connected iPhone.
# DEVICE defaults to the first connected physical iPhone.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /connected|available/ && !/simulated/ {for(i=1;i<=NF;i++) if ($$i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$$/) print $$i}' | head -1)
apple-install: apple-project
	@test -n "$(DEVICE)" || (echo "No iPhone connected"; exit 1)
	xcodebuild -project apple/CPRCoach.xcodeproj -scheme CPRCoach -configuration Debug \
	  -destination 'platform=iOS,id=$(DEVICE)' -derivedDataPath apple/.build -allowProvisioningUpdates build
	xcrun devicectl device install app --device $(DEVICE) apple/.build/Build/Products/Debug-iphoneos/CPRCoach.app

# iPhone relay only (no watch app inside): works before the watch is registered to your team.
apple-install-phone: apple-project
	@test -n "$(DEVICE)" || (echo "No iPhone connected"; exit 1)
	xcodebuild -project apple/CPRCoach.xcodeproj -scheme CPRCoachPhoneOnly -configuration Debug \
	  -destination 'platform=iOS,id=$(DEVICE)' -derivedDataPath apple/.build -allowProvisioningUpdates build
	xcrun devicectl device install app --device $(DEVICE) apple/.build/Build/Products/Debug-iphoneos/CPRCoachPhoneOnly.app
