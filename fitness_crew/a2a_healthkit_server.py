"""
fitness_crew/a2a_healthkit_server.py
────────────────────────────────────
A2A Server for the HealthKit Analyst Agent.

Publishes an Agent Card at /.well-known/agent.json and handles
A2A message/send requests via JSON-RPC.

Run standalone:  python a2a_healthkit_server.py
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
    "You are an expert health analyst specialising in Apple HealthKit metrics. "
    "You interpret steps, heart rate, active calories, and sleep data. "
    "You write detailed, data-driven health insights in clear markdown. "
    "Never give medical diagnoses."
)


def invoke_healthkit_agent(prompt: str, max_tokens: int = 700) -> str:
    """Call the HealthKit analyst via Groq."""
    resp = client.chat.completions.create(
        model=cfg.GROQ_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        temperature=0.3,
        max_tokens=max_tokens,
    )
    return resp.choices[0].message.content.strip()


# ── A2A AgentExecutor ─────────────────────────────────────────────────────────
class HealthKitAgentExecutor(AgentExecutor):
    """Handles incoming A2A tasks for health metric analysis."""

    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        query = context.get_user_input()
        try:
            result = invoke_healthkit_agent(query)
            parts = [Part(root=TextPart(text=str(result)))]
            await event_queue.enqueue_event(
                completed_task(
                    context.task_id,
                    context.context_id,
                    [new_artifact(parts, f"healthkit_{context.task_id}")],
                    [context.message],
                )
            )
        except Exception as e:
            from a2a.server.errors import ServerError
            raise ServerError(error=ValueError(f"HealthKit agent error: {e}")) from e

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        from a2a.server.errors import ServerError, UnsupportedOperationError
        raise ServerError(error=UnsupportedOperationError())


# ── Main ──────────────────────────────────────────────────────────────────────
def build_app(host: str = "0.0.0.0", port: int = cfg.HEALTHKIT_AGENT_PORT):
    """Build and return the A2A Starlette application."""
    capabilities = AgentCapabilities(streaming=False)

    skill = AgentSkill(
        id="analyze_health_metrics",
        name="Health Metrics Analyzer",
        description=(
            "Analyzes Apple HealthKit data including steps, heart rate, "
            "active calories, and sleep. Returns data-driven health insights."
        ),
        tags=["health", "healthkit", "metrics", "analysis"],
        examples=[
            "Analyze my health data: 8000 steps, 400 cal, HR 65 bpm, 7.5h sleep",
            "What do my metrics mean for my muscle gain goal?",
        ],
    )

    public_host = "localhost" if host in {"0.0.0.0", "::"} else host
    agent_host_url = os.getenv("HOST_OVERRIDE") or f"http://{public_host}:{port}"

    agent_card = AgentCard(
        name="healthkit_analyst_agent",
        description=(
            "Expert health analyst specializing in Apple HealthKit metrics. "
            "Interprets steps, heart rate, calories, and sleep data to "
            "provide data-driven health observations."
        ),
        url=agent_host_url,
        version="1.0.0",
        defaultInputModes=HealthKitAgentExecutor.SUPPORTED_CONTENT_TYPES,
        defaultOutputModes=HealthKitAgentExecutor.SUPPORTED_CONTENT_TYPES,
        capabilities=capabilities,
        skills=[skill],
    )

    request_handler = DefaultRequestHandler(
        agent_executor=HealthKitAgentExecutor(),
        task_store=InMemoryTaskStore(),
    )

    server = A2AStarletteApplication(
        agent_card=agent_card,
        http_handler=request_handler,
    )
    return server.build()


if __name__ == "__main__":
    port = cfg.HEALTHKIT_AGENT_PORT
    print(f"🫀 HealthKit Analyst A2A Server starting on port {port}…")
    app = build_app(port=port)
    uvicorn.run(app, host="0.0.0.0", port=port)
