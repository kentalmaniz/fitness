"""
fitness_crew/agents/health_kit_agent.py
────────────────────────────────────────
HealthKitAgent – analyses HealthKit JSON from the iOS app and returns
concise, data-driven health observations.
"""

from crewai import Agent
from langchain_groq import ChatGroq
from crew_config import GROQ_MODEL, require_groq_api_key


def create_healthkit_agent() -> Agent:
    llm = ChatGroq(
        api_key=require_groq_api_key(),
        model_name=GROQ_MODEL,
        temperature=0.3,
    )

    return Agent(
        role="Health Data Analyst",
        goal=(
            "Analyse real-time HealthKit data (steps, heart rate, calories, sleep) "
            "and surface brief, accurate, data-driven health observations."
        ),
        backstory=(
            "You are an expert health analyst who interprets Apple HealthKit metrics. "
            "You turn raw numbers into clear, doctor-friendly observations without "
            "giving medical diagnoses. You are precise and concise."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
