"""
fitness_crew/a2a_concierge.py
─────────────────────────────
A2A Concierge — Fitness Coaching Orchestrator.

Acts as an A2A *client* that discovers the 3 specialist agent servers
(HealthKit Analyst, Fitness Coach, QA Reviewer) via their Agent Cards,
then routes user requests to the right agents using A2A message/send.

Exposes the same REST surface as the legacy crew_server.py so the
iOS app works without changes.

Run:  python a2a_concierge.py
      (requires the 3 agent servers to be running — use start_a2a.py)
"""
from __future__ import annotations

import asyncio
import datetime
import json
import uuid
from contextlib import asynccontextmanager

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from a2a.client import A2ACardResolver, A2AClient
from a2a.types import (
    MessageSendParams,
    SendMessageRequest,
    SendMessageResponse,
    SendMessageSuccessResponse,
    Task,
    AgentCard,
)

import crew_config as cfg

# ── A2A Connection State ──────────────────────────────────────────────────────
remote_agent_urls: list[str] = [
    cfg.HEALTHKIT_AGENT_URL,
    cfg.COACH_AGENT_URL,
    cfg.QA_AGENT_URL,
]

# name -> A2AClient
agent_clients: dict[str, A2AClient] = {}
# name -> AgentCard
agent_cards: dict[str, AgentCard] = {}


async def discover_agents(max_retries: int = 10, delay: float = 2.0):
    """Discover all remote A2A agent cards."""
    async with httpx.AsyncClient(timeout=httpx.Timeout(timeout=30)) as http:
        for url in remote_agent_urls:
            for attempt in range(max_retries):
                try:
                    resolver = A2ACardResolver(base_url=url, httpx_client=http)
                    card = await resolver.get_agent_card()
                    a2a_client = A2AClient(
                        httpx_client=httpx.AsyncClient(timeout=httpx.Timeout(timeout=60)),
                        agent_card=card,
                    )
                    agent_clients[card.name] = a2a_client
                    agent_cards[card.name] = card
                    print(f"  ✅ Discovered: {card.name} @ {card.url}")
                    print(f"     Skills: {[s.name for s in card.skills]}")
                    break
                except (httpx.ConnectError, httpx.ReadError) as e:
                    if attempt < max_retries - 1:
                        print(f"  ⏳ Waiting for {url}… (attempt {attempt + 1}/{max_retries})")
                        await asyncio.sleep(delay)
                    else:
                        print(f"  ❌ Failed to discover agent at {url}: {e}")


async def send_a2a_task(agent_name: str, task_text: str) -> str:
    """Send a task to a remote A2A agent and return the text response."""
    if agent_name not in agent_clients:
        raise ValueError(f"Agent '{agent_name}' not discovered")

    client = agent_clients[agent_name]
    message_id = str(uuid.uuid4())
    context_id = str(uuid.uuid4())

    payload = {
        "message": {
            "role": "user",
            "parts": [{"type": "text", "text": task_text}],
            "messageId": message_id,
            "contextId": context_id,
        }
    }

    request = SendMessageRequest(
        id=message_id,
        params=MessageSendParams.model_validate(payload),
    )

    response: SendMessageResponse = await client.send_message(
        request=request
    )

    # Extract text from response
    if not isinstance(response.root, SendMessageSuccessResponse):
        raise RuntimeError(f"A2A error from {agent_name}: non-success response")

    result = response.root.result
    if isinstance(result, Task):
        # Extract text from task artifacts
        if result.artifacts:
            for artifact in result.artifacts:
                if artifact.parts:
                    texts = []
                    for part in artifact.parts:
                        if hasattr(part.root, "text"):
                            texts.append(part.root.text)
                    if texts:
                        return "\n".join(texts)
        # Fallback: check task history for messages
        if result.history:
            for msg in reversed(result.history):
                if msg.parts:
                    for part in msg.parts:
                        if hasattr(part.root, "text"):
                            return part.root.text
    return "(No response from agent)"


# ── Schemas (same as crew_server.py for backward compat) ─────────────────────
class HealthData(BaseModel):
    name:           str   = "User"
    steps:          int   = 0
    calories:       float = 0.0
    heart_rate:     float = 0.0
    sleep_hours:    float = 0.0
    active_minutes: int   = 0
    weight_kg:      float = 0.0
    goal:           str   = "General Fitness"
    weeks_active:   int   = 0
    workouts_done:  int   = 0
    streak_days:    int   = 0


class ChatRequest(BaseModel):
    message:     str        = Field(default="", max_length=1000)
    health_data: HealthData = Field(default_factory=HealthData)


class ChatResponse(BaseModel):
    response:    str
    agents_used: list[str]
    protocol:    str = "A2A"


class ReportResponse(BaseModel):
    report:      str
    agents_used: list[str]
    protocol:    str = "A2A"


# ── FastAPI App ───────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Discover A2A agents on startup."""
    print("\n🔍 Discovering A2A agents…")
    await discover_agents()
    print(f"\n🚀 Fitness Concierge ready — {len(agent_clients)} agents discovered\n")
    yield
    # Cleanup: close httpx clients
    for client in agent_clients.values():
        await client.httpx_client.aclose()


app = FastAPI(
    title="Fitness Concierge (A2A)",
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health_check():
    """Liveness check — includes discovered agent info."""
    return {
        "status": "ok",
        "protocol": "A2A",
        "agents_discovered": list(agent_cards.keys()),
        "agent_count": len(agent_clients),
    }


@app.get("/agents")
async def list_agents():
    """List all discovered A2A agent cards."""
    result = {}
    for name, card in agent_cards.items():
        result[name] = {
            "name": card.name,
            "description": card.description,
            "url": card.url,
            "version": card.version,
            "skills": [
                {
                    "id": s.id,
                    "name": s.name,
                    "description": s.description,
                    "tags": s.tags,
                }
                for s in card.skills
            ],
        }
    return result


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """Quick Q&A via A2A: HealthKit Agent → Coach Agent → QA Agent."""
    try:
        hd = req.health_data
        ctx = (
            f"Steps: {hd.steps}, Calories: {hd.calories:.0f} kcal, "
            f"HR: {hd.heart_rate:.0f} bpm, Sleep: {hd.sleep_hours:.1f}h, "
            f"Goal: {hd.goal}"
        )

        # Step 1: HealthKit Analyst via A2A
        analysis = await send_a2a_task(
            "healthkit_analyst_agent",
            f"Health data: {ctx}\nQuestion: \"{req.message}\"\n"
            "Give a concise 2-sentence data-driven health observation.",
        )

        # Step 2: Fitness Coach via A2A
        coaching = await send_a2a_task(
            "fitness_coach_agent",
            f"Health analysis: {analysis}\nQuestion: \"{req.message}\"\n"
            "Write a motivating, actionable 3-sentence coaching reply.",
        )

        # Step 3: QA Reviewer via A2A
        final = await send_a2a_task(
            "qa_reviewer_agent",
            f"Draft reply to polish:\n{coaching}",
        )

        return ChatResponse(
            response=final,
            agents_used=[
                "healthkit_analyst_agent",
                "fitness_coach_agent",
                "qa_reviewer_agent",
            ],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/motivate", response_model=ChatResponse)
async def motivate(req: ChatRequest):
    """Daily motivation via A2A: Coach Agent → QA Agent."""
    try:
        hd = req.health_data
        draft = await send_a2a_task(
            "fitness_coach_agent",
            f"Steps: {hd.steps}, Cal: {hd.calories:.0f}, HR: {hd.heart_rate:.0f} bpm, "
            f"Sleep: {hd.sleep_hours:.1f}h, Goal: {hd.goal}.\n"
            "Write a short personalised daily motivational message (2 sentences).",
        )

        final = await send_a2a_task(
            "qa_reviewer_agent",
            f"Polish this message:\n{draft}",
        )

        return ChatResponse(
            response=final,
            agents_used=["fitness_coach_agent", "qa_reviewer_agent"],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/report", response_model=ReportResponse)
async def full_report(req: ChatRequest):
    """
    Full Personalized Coaching Report via A2A.
    HealthKit Agent → Coach Agent → QA Agent (same pipeline as crew_server.py).
    """
    try:
        hd = req.health_data
        today = datetime.date.today().strftime("%d %B %Y")

        extra = f"\nAdditional intake details: {req.message}" if req.message else ""
        health_ctx = (
            f"Name: {hd.name} | Goal: {hd.goal} | Date: {today}\n"
            f"Steps today: {hd.steps} | Active calories: {hd.calories:.0f} kcal\n"
            f"Heart rate: {hd.heart_rate:.0f} bpm | Sleep: {hd.sleep_hours:.1f} h\n"
            f"Active minutes: {hd.active_minutes} | Weight: {hd.weight_kg:.1f} kg\n"
            f"Weeks active: {hd.weeks_active} | Workouts completed: {hd.workouts_done} "
            f"| Streak: {hd.streak_days} days{extra}"
        )

        # Task 1: HealthKit Agent → health insights via A2A
        hk_section = await send_a2a_task(
            "healthkit_analyst_agent",
            f"{health_ctx}\n\n"
            "Write a detailed '### HealthKit Insights' markdown section that covers:\n"
            "- Analysis of each metric (steps, calories, heart rate, sleep)\n"
            "- What the numbers mean for the user's goal\n"
            "- 2-3 specific data-driven recommendations\n"
            "Use bullet points and sub-headers. Be specific and data-driven.",
        )

        # Task 2: Coach Agent → plan + nutrition + motivation via A2A
        ui_section = await send_a2a_task(
            "fitness_coach_agent",
            f"{health_ctx}\n\n"
            "Write THREE detailed markdown sections:\n\n"
            "### Personalized Motivational Message\n"
            "(Write a warm, specific motivational message addressing the user by name)\n\n"
            "### QA-Verified Workout Strategy Summary\n"
            "(Create a detailed weekly workout split matching their goal, with days, "
            "exercises, sets/reps)\n\n"
            "### Nutrition Approach\n"
            "(Calculate daily calories and macros for their goal, provide a sample "
            "meal outline)\n\n"
            "### App Experience Improvements\n"
            "(3-4 specific UI/UX recommendations for their fitness app)\n\n"
            "### This Week's Top 5 Actions\n"
            "(Numbered list of the 5 most impactful actions they should take this week)"
            "\n\nBe specific, use the user's name, reference their actual data.",
        )

        # Task 3: QA Agent → assemble full report via A2A
        final_report = await send_a2a_task(
            "qa_reviewer_agent",
            f"Assemble a complete, polished Personalized Coaching Report in markdown.\n\n"
            f"User info: {health_ctx}\n"
            f"Today's date: {today}\n\n"
            f"=== HEALTHKIT INSIGHTS (from HealthKit Agent) ===\n{hk_section}\n\n"
            f"=== COACHING CONTENT (from Coach Agent) ===\n{ui_section}\n\n"
            "Instructions:\n"
            "1. Start with this exact header block:\n"
            f"# {hd.name}'s Personalized Coaching Report\n"
            f"## Date: {today}\n"
            "## QA Status: ![QA PASS](https://img.shields.io/badge/QA-PASS-success)\n\n"
            "2. Add a brief intro paragraph from 'your Head Fitness Coach'.\n"
            "3. Include ALL sections from both agents, in this order:\n"
            "   - Personalized Motivational Message\n"
            "   - QA-Verified Workout Strategy Summary\n"
            "   - Nutrition Approach\n"
            "   - HealthKit Insights\n"
            "   - App Experience Improvements\n"
            "   - This Week's Top 5 Actions\n"
            "   - Motivational Closing\n"
            "4. Add a '### Progress Highlights' section based on the user data.\n"
            "5. Bold key numbers and action items.\n"
            "6. Output ONLY the final markdown report — nothing else.",
        )

        return ReportResponse(
            report=final_report,
            agents_used=[
                "healthkit_analyst_agent",
                "fitness_coach_agent",
                "qa_reviewer_agent",
            ],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = cfg.CONCIERGE_PORT
    print(f"\n🏋️ Fitness Concierge (A2A Client) starting on port {port}…")
    uvicorn.run(
        "a2a_concierge:app",
        host="0.0.0.0",
        port=port,
        reload=False,
    )
