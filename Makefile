# make dev | make sim | make test | make build
PY := backend/.venv/bin/python
SCENARIO ?= good

.PHONY: setup dev backend web sim test lint build

setup:
	cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd web && npm install

# Runs uvicorn on 0.0.0.0:8000 and vite on 5173; Ctrl-C stops both.
dev:
	@trap 'kill 0' INT TERM EXIT; \
	(cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload) & \
	(cd web && npm run dev) & \
	wait

backend:
	cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

web:
	cd web && npm run dev

sim:
	cd backend && .venv/bin/python -m tools.sim_watch --scenario $(SCENARIO)

test:
	cd backend && .venv/bin/pytest -q
	cd web && npm run typecheck && npm test

lint:
	cd backend && .venv/bin/ruff check app tests tools

build:
	cd web && npm run build
