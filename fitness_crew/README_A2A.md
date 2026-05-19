# Fitness Crew — A2A Protocol Integration

## Overview

This directory now supports the **Agent-to-Agent (A2A) protocol**, enabling your 3 fitness agents to communicate as independent, discoverable services — just like the [Google A2A purchasing concierge codelab](https://codelabs.developers.google.com/intro-a2a-purchasing-concierge).

### Architecture

```
┌─────────────────────────────────────────────┐
│  iOS App (SwiftUI)                          │
│  └─ POST /chat, /motivate, /report          │
│       ↓                                     │
│  Fitness Concierge (A2A Client · :8000)     │
│  └─ Discovers + routes to agent servers     │
│       ↓          ↓           ↓              │
│  ┌──────────┐┌──────────┐┌──────────┐       │
│  │ HealthKit ││  Coach   ││    QA    │       │
│  │  :8001   ││  :8002   ││  :8003   │       │
│  │ A2A Srv  ││ A2A Srv  ││ A2A Srv  │       │
│  └──────────┘└──────────┘└──────────┘       │
│          All powered by Groq LLM            │
└─────────────────────────────────────────────┘
```

## Quick Start

### 1. Install dependencies

```bash
cd fitness_crew
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

### 2. Set your Groq API key (if not already in crew_config.py)

```bash
export GROQ_API_KEY="gsk_your_key_here"
```

`crew_config.py` intentionally does not store a fallback key. Keep the key in
your shell environment so it can be rotated without editing source.

### 3. Start the A2A stack (all 4 services)

```bash
python3 start_a2a.py
```

This starts:
| Service | Port | Role |
|---------|------|------|
| HealthKit Analyst | 8001 | A2A Server — health data analysis |
| Fitness Coach | 8002 | A2A Server — workout/nutrition plans |
| QA Reviewer | 8003 | A2A Server — safety review & polish |
| Fitness Concierge | 8000 | A2A Client — orchestrator (iOS app talks here) |

### 4. Verify agent cards

```bash
# HealthKit Analyst
curl http://localhost:8001/.well-known/agent.json | python -m json.tool

# Fitness Coach
curl http://localhost:8002/.well-known/agent.json | python -m json.tool

# QA Reviewer
curl http://localhost:8003/.well-known/agent.json | python -m json.tool
```

### 5. Test the concierge

```bash
# Health check (shows discovered agents)
curl http://localhost:8000/health | python -m json.tool

# List all agent cards
curl http://localhost:8000/agents | python -m json.tool

# Chat (3-agent pipeline via A2A)
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "How can I improve my step count?",
    "health_data": {
      "name": "Justin",
      "steps": 4200,
      "calories": 310,
      "heart_rate": 72,
      "sleep_hours": 7.5,
      "goal": "Muscle Gain"
    }
  }'

# Full report
curl -X POST http://localhost:8000/report \
  -H "Content-Type: application/json" \
  -d '{
    "health_data": {
      "name": "Justin",
      "steps": 8000,
      "calories": 400,
      "heart_rate": 65,
      "sleep_hours": 7.5,
      "goal": "Muscle Gain",
      "weight_kg": 78,
      "weeks_active": 4,
      "workouts_done": 12,
      "streak_days": 5
    }
  }'
```

## How A2A Works Here

### Agent Cards (Discovery)

Each agent server publishes a JSON "Agent Card" at `/.well-known/agent.json` describing:
- **Name** — unique identifier (e.g., `healthkit_analyst_agent`)
- **Description** — what the agent does
- **Skills** — specific capabilities with examples
- **URL** — where to send A2A messages
- **Capabilities** — streaming support, etc.

The concierge reads these cards at startup to know which agents are available and what they can do.

### Message Flow (JSON-RPC)

When you call `POST /chat`, the concierge:

1. **Sends A2A message** to `healthkit_analyst_agent` with your health data
2. Receives a **Task** result with the analysis as an artifact
3. **Sends A2A message** to `fitness_coach_agent` with the analysis
4. Receives the coaching response
5. **Sends A2A message** to `qa_reviewer_agent` to polish the final reply
6. Returns the polished response to the iOS app

Each A2A message uses the standard `message/send` JSON-RPC method:

```json
{
  "id": "abc-123",
  "jsonrpc": "2.0",
  "method": "message/send",
  "params": {
    "message": {
      "role": "user",
      "parts": [{"type": "text", "text": "..."}],
      "messageId": "msg-456",
      "contextId": "session-789"
    }
  }
}
```

## Files

| File | Description |
|------|-------------|
| `a2a_healthkit_server.py` | A2A Server — HealthKit Analyst (port 8001) |
| `a2a_coach_server.py` | A2A Server — Fitness Coach (port 8002) |
| `a2a_qa_server.py` | A2A Server — QA Reviewer (port 8003) |
| `a2a_concierge.py` | A2A Client — Fitness Concierge (port 8000) |
| `start_a2a.py` | Launcher — starts all 4 services |
| `crew_config.py` | Shared config (API keys, ports, URLs) |
| `crew_server.py` | Legacy direct-call server (still works) |

## Legacy Mode

The original `crew_server.py` still works independently if you don't need A2A:

```bash
python3 crew_server.py  # Direct Groq calls, no A2A protocol
```

## iOS App Compatibility

The A2A concierge exposes the **exact same REST endpoints** on the same port (8000):
- `POST /chat` — 3-agent Q&A
- `POST /motivate` — daily motivation
- `POST /report` — full coaching report
- `GET /health` — liveness check

Your iOS app works without any code changes.
