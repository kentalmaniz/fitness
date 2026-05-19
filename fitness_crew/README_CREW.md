# Fitness CrewAI Server — Setup Guide

## 1. Prerequisites
- Python 3.10+
- A [GroqCloud](https://console.groq.com) API key

## 2. Install dependencies
```bash
cd fitness_crew
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

## 3. Set your Groq API key
Export it as an environment variable:
```bash
export GROQ_API_KEY="gsk_your_key_here"
```

## 4. Start the server
```bash
cd fitness_crew
python3 crew_server.py
# Server runs at http://localhost:8000
```

## 5. Test it
```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"How can I improve my step count?","health_data":{"steps":4200,"calories":310,"heart_rate":72}}'
```

## 6. Agents
| Agent | Role | Temperature |
|-------|------|-------------|
| HealthKitAgent | Analyses HealthKit JSON data | 0.3 |
| UIAgent | Generates motivational coaching text | 0.7 |
| QAAgent | Safety-reviews & polishes the final reply | 0.1 |

## 7. iOS App endpoints used
| Endpoint | When called |
|----------|------------|
| `POST /chat` | AI Coach chat tab — full 3-agent pipeline |
| `POST /motivate` | Dashboard — daily motivational message |
| `GET /health` | Liveness check |

## 8. Xcode — Add new Swift files
The new `.swift` files are in `fitness/fitness/`. Drag them into the Xcode project navigator under the **fitness** group so they are compiled into the target:
- `Models.swift`
- `Services.swift`
- `ViewModels.swift`
- `DashboardView.swift`
- `FitnessPlanView.swift`
- `HealthStatsView.swift`
- `AIChatView.swift`

Then add the **HealthKit** capability:  
Xcode → Target → Signing & Capabilities → **+ HealthKit**

Also add to `Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>Used to display your fitness stats in the app.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Used to log workout activity.</string>
```
