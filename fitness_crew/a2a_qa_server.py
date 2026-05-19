"""
fitness_crew/a2a_qa_server.py
─────────────────────────────
A2A Server for the QA Reviewer Agent.

Publishes an Agent Card at /.well-known/agent.json and handles
A2A message/send requests via JSON-RPC.

Run standalone:  python a2a_qa_server.py
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
    "You are a senior fitness and health safety reviewer and report editor. "
    "You receive draft content from other agents and compile it into a single, "
    "polished, professional markdown coaching report. "
    "Ensure safety, accuracy, and a cohesive motivational tone. "
    "Output ONLY the final markdown — no commentary, no preamble."
)


def invoke_qa_agent(prompt: str, max_tokens: int = 2000) -> str:
    """Call the QA reviewer via Groq."""
    resp = client.chat.completions.create(
        model=cfg.GROQ_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        temperature=0.2,
        max_tokens=max_tokens,
    )
    return resp.choices[0].message.content.strip()


# ── A2A AgentExecutor ─────────────────────────────────────────────────────────
class QAAgentExecutor(AgentExecutor):
    """Handles incoming A2A tasks for quality review."""

    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        query = context.get_user_input()
        try:
            result = invoke_qa_agent(query)
            parts = [Part(root=TextPart(text=str(result)))]
            await event_queue.enqueue_event(
                completed_task(
                    context.task_id,
                    context.context_id,
                    [new_artifact(parts, f"qa_{context.task_id}")],
                    [context.message],
                )
            )
        except Exception as e:
            from a2a.server.errors import ServerError
            raise ServerError(error=ValueError(f"QA agent error: {e}")) from e

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        from a2a.server.errors import ServerError, UnsupportedOperationError
        raise ServerError(error=UnsupportedOperationError())


# ── Main ──────────────────────────────────────────────────────────────────────
def build_app(host: str = "0.0.0.0", port: int = cfg.QA_AGENT_PORT):
    """Build and return the A2A Starlette application."""
    capabilities = AgentCapabilities(streaming=False)

    skill = AgentSkill(
        id="review_and_polish",
        name="Content Reviewer & Polisher",
        description=(
            "Reviews AI-generated fitness content for safety, accuracy, "
            "and tone. Compiles drafts into a polished professional report."
        ),
        tags=["qa", "review", "polish", "safety", "report"],
        examples=[
            "Review and polish this workout plan for safety",
            "Compile these agent outputs into a final coaching report",
        ],
    )

    public_host = "localhost" if host in {"0.0.0.0", "::"} else host
    agent_host_url = os.getenv("HOST_OVERRIDE") or f"http://{public_host}:{port}"

    agent_card = AgentCard(
        name="qa_reviewer_agent",
        description=(
            "Senior fitness and health safety reviewer. Reviews content "
            "from other agents for safety, accuracy, and tone, then "
            "assembles polished professional coaching reports."
        ),
        url=agent_host_url,
        version="1.0.0",
        defaultInputModes=QAAgentExecutor.SUPPORTED_CONTENT_TYPES,
        defaultOutputModes=QAAgentExecutor.SUPPORTED_CONTENT_TYPES,
        capabilities=capabilities,
        skills=[skill],
    )

    request_handler = DefaultRequestHandler(
        agent_executor=QAAgentExecutor(),
        task_store=InMemoryTaskStore(),
    )

    server = A2AStarletteApplication(
        agent_card=agent_card,
        http_handler=request_handler,
    )
    return server.build()


if __name__ == "__main__":
    port = cfg.QA_AGENT_PORT
    print(f"✅ QA Reviewer A2A Server starting on port {port}…")
    app = build_app(port=port)
    uvicorn.run(app, host="0.0.0.0", port=port)
