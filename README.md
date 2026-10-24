# CPR Coach

Real-time CPR feedback from an Apple Watch, a webcam and a laptop. **Training tool – not a medical device.**

See [PRD.md](PRD.md) for the full spec.

## Setup

Requires Python 3.11+ and Node 20+.

```bash
make setup
```

## Run

```bash
make dev
```

Opens the dashboard at http://localhost:5173 (API on :8000, bound to 0.0.0.0 so the phone can reach it).

- Simulator: `make sim SCENARIO=shallow` *(M2)*
- Tests: `make test`
- Production build: `make build`, then the backend serves `web/dist` at http://localhost:8000

## Calibrate

*(M4)*

## Demo

*(M5)*

## Troubleshooting

*(M5)*
