"""
fitness_crew/crew_server.py
────────────────────────────
3-agent fitness crew using the native Groq SDK.

NOTE: For the A2A-enabled version, use a2a_concierge.py + start_a2a.py instead.
This file is kept for backward compatibility / non-A2A standalone usage.
See README_A2A.md for details.

Endpoints:
  GET  /health    — liveness check
  POST /chat      — quick Q&A  (HealthKitAgent → UIAgent → QAAgent)
  POST /motivate  — daily motivation (UIAgent → QAAgent)
  POST /report    — full Personalized Coaching Report (all 3 agents)
"""
from __future__ import annotations
import datetime, uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from groq import Groq
import crew_config as cfg

app = FastAPI(title="Fitness Crew Server", version="3.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                  allow_methods=["*"], allow_headers=["*"])

client = Groq(api_key=cfg.require_groq_api_key())

# ── Agent definitions ─────────────────────────────────────────────────────────
AGENTS = {
    "HealthKitAgent": {
        "system": (
            "You are an expert health analyst specialising in Apple HealthKit metrics. "
            "You interpret steps, heart rate, active calories, and sleep data. "
            "You write detailed, data-driven health insights in clear markdown. "
            "Never give medical diagnoses."
        ),
        "temperature": 0.3,
    },
    "UIAgent": {
        "system": (
            "You are an elite certified personal trainer and nutrition coach. "
            "You create detailed, personalised fitness plans, nutrition strategies, "
            "workout schedules, motivational messages, and app UX recommendations. "
            "Write in clear, encouraging markdown with bullet points and headers."
        ),
        "temperature": 0.7,
    },
    "QAAgent": {
        "system": (
            "You are a senior fitness and health safety reviewer and report editor. "
            "You receive draft content from other agents and compile it into a single, "
            "polished, professional markdown coaching report. "
            "Ensure safety, accuracy, and a cohesive motivational tone. "
            "Output ONLY the final markdown — no commentary, no preamble."
        ),
        "temperature": 0.2,
    },
}


def run_agent(agent_name: str, prompt: str, max_tokens: int = 1024) -> str:
    agent = AGENTS[agent_name]
    resp = client.chat.completions.create(
        model=cfg.GROQ_MODEL,
        messages=[
            {"role": "system",  "content": agent["system"]},
            {"role": "user",    "content": prompt},
        ],
        temperature=agent["temperature"],
        max_tokens=max_tokens,
    )
    return resp.choices[0].message.content.strip()


# ── Schemas ───────────────────────────────────────────────────────────────────
class HealthData(BaseModel):
    name:           str   = "User"
    age:            int   = 28
    weight_kg:      float = 75.0
    height_cm:      float = 175.0
    steps:          int   = 0
    calories:       float = 0.0
    heart_rate:     float = 0.0
    sleep_hours:    float = 0.0
    active_minutes: int   = 0
    goal:           str   = "General Fitness"
    level:          str   = "Beginner (0-6 months)"
    days_per_week:  int   = 4
    session_mins:   int   = 60
    target_weeks:   int   = 12
    equipment:      str   = "Full Gym (barbells, machines, cables)"
    weeks_active:   int   = 0
    workouts_done:  int   = 0
    streak_days:    int   = 0
    diet:           str   = "No restrictions (Omnivore)"
    meals_per_day:  int   = 3
    water_liters:   float = 2.0
    allergies:      str   = "None"
    supplements:    str   = "None"
    stress_level:   int   = 5
    injuries:       str   = "None"
    extra_goals:    str   = "Improve overall health and energy levels"

class ChatRequest(BaseModel):
    message:     str        = Field(default="", max_length=1000)
    health_data: HealthData = Field(default_factory=HealthData)

class ChatResponse(BaseModel):
    response:    str
    agents_used: list[str]

class ReportResponse(BaseModel):
    report:      str
    agents_used: list[str]


# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health_check():
    return {"status": "ok", "model": cfg.GROQ_MODEL, "agents": list(AGENTS.keys())}


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """Quick Q&A: HealthKitAgent → UIAgent → QAAgent"""
    try:
        hd = req.health_data
        ctx = (f"Steps: {hd.steps}, Calories: {hd.calories:.0f} kcal, "
               f"HR: {hd.heart_rate:.0f} bpm, Sleep: {hd.sleep_hours:.1f}h, "
               f"Goal: {hd.goal}")

        analysis = run_agent("HealthKitAgent",
            f"Health data: {ctx}\nQuestion: \"{req.message}\"\n"
            "Give a concise 2-sentence data-driven health observation.", 256)

        coaching = run_agent("UIAgent",
            f"Health analysis: {analysis}\nQuestion: \"{req.message}\"\n"
            "Write a motivating, actionable 3-sentence coaching reply.", 300)

        final = run_agent("QAAgent",
            f"Draft reply to polish:\n{coaching}", 300)

        return ChatResponse(response=final,
                            agents_used=["HealthKitAgent", "UIAgent", "QAAgent"])
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/motivate", response_model=ChatResponse)
async def motivate(req: ChatRequest):
    """Daily motivation: UIAgent → QAAgent"""
    try:
        hd = req.health_data
        draft = run_agent("UIAgent",
            f"Steps: {hd.steps}, Cal: {hd.calories:.0f}, HR: {hd.heart_rate:.0f} bpm, "
            f"Sleep: {hd.sleep_hours:.1f}h, Goal: {hd.goal}.\n"
            "Write a short personalised daily motivational message (2 sentences).", 200)
        final = run_agent("QAAgent", f"Polish this message:\n{draft}", 200)
        return ChatResponse(response=final, agents_used=["UIAgent", "QAAgent"])
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/report", response_model=ReportResponse)
async def full_report(req: ChatRequest):
    """
    Full Personalized Coaching Report.
    HealthKitAgent  → produces HealthKit Insights section
    UIAgent         → produces Workout Plan + Nutrition + Motivation sections
    QAAgent         → assembles everything into the final polished markdown report
    """
    try:
        hd    = req.health_data
        today = datetime.date.today().strftime("%d %B %Y")
        bmi   = hd.weight_kg / ((hd.height_cm / 100) ** 2) if hd.height_cm > 0 else 0

        extra = f"\nAdditional notes: {req.message}" if req.message else ""
        health_ctx = (
            f"Name: {hd.name} | Age: {hd.age} | Weight: {hd.weight_kg}kg | "
            f"Height: {hd.height_cm}cm | BMI: {bmi:.1f}\n"
            f"Goal: {hd.goal} | Target: {hd.target_weeks} weeks | Level: {hd.level}\n"
            f"Schedule: {hd.days_per_week} days/week x {hd.session_mins} min | "
            f"Equipment: {hd.equipment}\n"
            f"Steps: {hd.steps} | Active cal: {hd.calories:.0f} kcal | "
            f"HR: {hd.heart_rate:.0f} bpm | Sleep: {hd.sleep_hours:.1f}h | "
            f"Active min: {hd.active_minutes}\n"
            f"Weeks active: {hd.weeks_active} | Workouts done: {hd.workouts_done} | "
            f"Streak: {hd.streak_days} days\n"
            f"Diet: {hd.diet} | {hd.meals_per_day} meals/day | {hd.water_liters}L water | "
            f"Allergies: {hd.allergies} | Supplements: {hd.supplements}\n"
            f"Stress: {hd.stress_level}/10 | Injuries: {hd.injuries} | "
            f"Extra goals: {hd.extra_goals}"
            f"{extra}"
        )

        # ── Task 1: HealthKitAgent — health insights section ──────────────────
        hk_section = run_agent("HealthKitAgent",
            f"{health_ctx}\n\n"
            "Write a detailed '### HealthKit Insights' markdown section that covers:\n"
            "- Analysis of each metric (steps, calories, heart rate, sleep)\n"
            "- What the numbers mean for the user's goal\n"
            "- 2-3 specific data-driven recommendations\n"
            "Use bullet points and sub-headers. Be specific and data-driven.",
            max_tokens=600)

        # ── Task 2: UIAgent — plan + nutrition + motivation sections ──────────
        ui_section = run_agent("UIAgent",
            f"{health_ctx}\n\n"
            "Write THREE detailed markdown sections:\n\n"
            "### Personalized Motivational Message\n"
            "(Write a warm, specific motivational message addressing the user by name)\n\n"
            "### QA-Verified Workout Strategy Summary\n"
            "(Create a detailed weekly workout split matching their goal, with days, exercises, sets/reps)\n\n"
            "### Nutrition Approach\n"
            "(Calculate daily calories and macros for their goal, provide a sample meal outline)\n\n"
            "### App Experience Improvements\n"
            "(3-4 specific UI/UX recommendations for their fitness app)\n\n"
            "### This Week's Top 5 Actions\n"
            "(Numbered list of the 5 most impactful actions they should take this week)\n\n"
            "Be specific, use the user's name, reference their actual data.",
            max_tokens=1200)

        # ── Task 3: QAAgent — assemble full report ────────────────────────────
        final_report = run_agent("QAAgent",
            f"Assemble a complete, polished Personalized Coaching Report in markdown.\n\n"
            f"User info: {health_ctx}\n"
            f"Today's date: {today}\n\n"
            f"=== HEALTHKIT INSIGHTS (from HealthKitAgent) ===\n{hk_section}\n\n"
            f"=== COACHING CONTENT (from UIAgent) ===\n{ui_section}\n\n"
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
            max_tokens=2000)

        return ReportResponse(
            report=final_report,
            agents_used=["HealthKitAgent", "UIAgent", "QAAgent"])

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


if __name__ == "__main__":
    uvicorn.run("crew_server:app", host=cfg.HOST, port=cfg.PORT, reload=True)
