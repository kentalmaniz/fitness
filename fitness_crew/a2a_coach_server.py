"""
fitness_crew/a2a_coach_server.py
────────────────────────────────
A2A Server for the Fitness Coach (UI) Agent.

Publishes an Agent Card at /.well-known/agent.json and handles
A2A message/send requests via JSON-RPC.

Run standalone:  python a2a_coach_server.py
"""
from __future__ import annotations

import os
import uvicorn
from groq import Groq

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore
from a2a.server.apps import A2AStarletteApplication
from a2a.types import (
    AgentCard,
    AgentCapabilities,
    AgentSkill,
    Part,
    TextPart,
)
from a2a.utils import new_artifact, completed_task
import crew_config as cfg

# ── Groq client ───────────────────────────────────────────────────────────────
client = Groq(api_key=cfg.require_groq_api_key())

SYSTEM_PROMPT = (
    "You are an elite certified personal trainer and nutrition coach. "
    "You create detailed, personalised fitness plans, nutrition strategies, "
    "workout schedules, motivational messages, and app UX recommendations. "
    "Write in clear, encouraging markdown with bullet points and headers."
)


def invoke_coach_agent(prompt: str, max_tokens: int = 1400) -> str:
    """Call the Fitness Coach via Groq."""
    resp = client.chat.completions.create(
        model=cfg.GROQ_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        temperature=0.7,
        max_tokens=max_tokens,
    )
    return resp.choices[0].message.content.strip()


# ── A2A AgentExecutor ─────────────────────────────────────────────────────────
class CoachAgentExecutor(AgentExecutor):
    """Handles incoming A2A tasks for fitness coaching."""

    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        query = context.get_user_input()
        try:
            result = invoke_coach_agent(query)
            parts = [Part(root=TextPart(text=str(result)))]
            await event_queue.enqueue_event(
                completed_task(
                    context.task_id,
                    context.context_id,
                    [new_artifact(parts, f"coach_{context.task_id}")],
                    [context.message],
                )
            )
        except Exception as e:
            from a2a.server.errors import ServerError
            raise ServerError(error=ValueError(f"Coach agent error: {e}")) from e

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        from a2a.server.errors import ServerError, UnsupportedOperationError
        raise ServerError(error=UnsupportedOperationError())


# ── Main ──────────────────────────────────────────────────────────────────────
def build_app(host: str = "0.0.0.0", port: int = cfg.COACH_AGENT_PORT):
    """Build and return the A2A Starlette application."""
    capabilities = AgentCapabilities(streaming=False)

    skills = [
        AgentSkill(
            id="create_workout_plan",
            name="Workout Plan Creator",
            description=(
                "Creates personalized weekly workout plans with exercises, "
                "sets, reps, and scheduling based on user goals and fitness level."
            ),
            tags=["workout", "exercise", "plan", "training"],
            examples=[
                "Create a 4-day muscle gain workout split for intermediate level",
                "Design a HIIT plan for weight loss with bodyweight exercises",
            ],
        ),
        AgentSkill(
            id="create_nutrition_plan",
            name="Nutrition Plan Creator",
            description=(
                "Calculates daily calories and macros, creates meal plans "
                "matching dietary preferences and fitness goals."
            ),
            tags=["nutrition", "diet", "macros", "meal plan"],
            examples=[
                "Calculate macros for muscle gain at 75kg bodyweight",
                "Create a vegan meal plan for 2500 calories/day",
            ],
        ),
        AgentSkill(
            id="generate_motivation",
            name="Motivational Message Generator",
            description=(
                "Crafts personalized, encouraging motivational messages "
                "based on user's progress and health data."
            ),
            tags=["motivation", "encouragement", "coaching"],
            examples=[
                "Write a motivational message for someone who hit 10k steps",
                "Encourage a user who missed their workout yesterday",
            ],
        ),
    ]

    public_host = "localhost" if host in {"0.0.0.0", "::"} else host
    agent_host_url = os.getenv("HOST_OVERRIDE") or f"http://{public_host}:{port}"

    agent_card = AgentCard(
        name="fitness_coach_agent",
        description=(
            "Elite certified personal trainer and nutrition coach. "
            "Creates workout plans, nutrition strategies, motivational "
            "messages, and app UX recommendations."
        ),
        url=agent_host_url,
        version="1.0.0",
        defaultInputModes=CoachAgentExecutor.SUPPORTED_CONTENT_TYPES,
        defaultOutputModes=CoachAgentExecutor.SUPPORTED_CONTENT_TYPES,
        capabilities=capabilities,
        skills=skills,
    )

    request_handler = DefaultRequestHandler(
        agent_executor=CoachAgentExecutor(),
        task_store=InMemoryTaskStore(),
    )

    server = A2AStarletteApplication(
        agent_card=agent_card,
        http_handler=request_handler,
    )
    return server.build()


if __name__ == "__main__":
    port = cfg.COACH_AGENT_PORT
    print(f"💪 Fitness Coach A2A Server starting on port {port}…")
    app = build_app(port=port)
    uvicorn.run(app, host="0.0.0.0", port=port)
