"""
fitness_crew/crew_config.py

GroqCloud + CrewAI/A2A configuration.
Set GROQ_API_KEY in your shell before starting the services.
"""

import os

# GroqCloud
GROQ_API_KEY: str | None = os.getenv("GROQ_API_KEY")
GROQ_MODEL: str = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")


def require_groq_api_key() -> str:
    """Return the configured Groq API key or fail with a clear setup message."""
    if not GROQ_API_KEY:
        raise RuntimeError(
            "GROQ_API_KEY is not set. Run: export GROQ_API_KEY='your_groq_key'"
        )
    return GROQ_API_KEY

# Legacy server (crew_server.py)
HOST: str = "0.0.0.0"
PORT: int = 8000

# A2A Agent Ports
HEALTHKIT_AGENT_PORT: int = 8001
COACH_AGENT_PORT:     int = 8002
QA_AGENT_PORT:        int = 8003
CONCIERGE_PORT:       int = 8000

# A2A Agent URLs (local)
HEALTHKIT_AGENT_URL: str = f"http://localhost:{HEALTHKIT_AGENT_PORT}"
COACH_AGENT_URL:     str = f"http://localhost:{COACH_AGENT_PORT}"
QA_AGENT_URL:        str = f"http://localhost:{QA_AGENT_PORT}"
