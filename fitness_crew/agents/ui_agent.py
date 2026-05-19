"""
fitness_crew/agents/ui_agent.py
────────────────────────────────
UIAgent – generates motivational, personalised fitness UI content and
chat replies based on the HealthKitAgent's analysis.
"""

from crewai import Agent
from langchain_groq import ChatGroq
from crew_config import GROQ_MODEL, require_groq_api_key


def create_ui_agent() -> Agent:
    llm = ChatGroq(
        api_key=require_groq_api_key(),
        model_name=GROQ_MODEL,
        temperature=0.7,
    )

    return Agent(
        role="Fitness Motivation Coach",
        goal=(
            "Craft uplifting, personalised fitness messages and actionable advice "
            "that keep users engaged with their health journey."
        ),
        backstory=(
            "You are an enthusiastic, certified personal trainer and life coach. "
            "You blend empathy with evidence-based fitness knowledge to create "
            "responses that feel like a conversation with a supportive coach — "
            "never preachy, always encouraging."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
