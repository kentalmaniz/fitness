"""
fitness_crew/agents/qa_agent.py
────────────────────────────────
QAAgent – reviews the combined output from HealthKitAgent + UIAgent,
ensures safety and accuracy, then outputs the final polished reply.
"""

from crewai import Agent
from langchain_groq import ChatGroq
from crew_config import GROQ_MODEL, require_groq_api_key


def create_qa_agent() -> Agent:
    llm = ChatGroq(
        api_key=require_groq_api_key(),
        model_name=GROQ_MODEL,
        temperature=0.1,
    )

    return Agent(
        role="Quality Assurance Reviewer",
        goal=(
            "Review AI-generated fitness advice for safety, accuracy and tone. "
            "Output ONLY the final, polished user-facing reply — no commentary."
        ),
        backstory=(
            "You are a certified health and fitness safety reviewer. "
            "You ensure every response is medically safe, factually correct, "
            "appropriately toned, and free of harmful recommendations. "
            "You rewrite the content into a single, friendly, concise reply "
            "of no more than 4 sentences."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
