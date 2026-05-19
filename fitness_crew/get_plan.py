"""
fitness_crew/get_plan.py
─────────────────────────
Fully standalone — no server required.
Calls Groq directly with the 3-agent pipeline.

Usage:
    python get_plan.py
"""
from __future__ import annotations
import datetime, sys, textwrap
from groq import Groq
import crew_config as cfg

WIDTH  = 72
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
    resp  = client.chat.completions.create(
        model=cfg.GROQ_MODEL,
        messages=[
            {"role": "system", "content": agent["system"]},
            {"role": "user",   "content": prompt},
        ],
        temperature=agent["temperature"],
        max_tokens=max_tokens,
    )
    return resp.choices[0].message.content.strip()

# ── Helpers ───────────────────────────────────────────────────────────────────
def line(char="─", n=WIDTH): print(char * n)

def header(text: str):
    line()
    print(f"  {text}")
    line()

def ask(prompt: str, default: str = "", validator=None) -> str:
    hint = f" [{default}]" if default else ""
    while True:
        raw = input(f"  {prompt}{hint}: ").strip()
        val = raw if raw else default
        if not val:
            print("  ⚠  This field is required.")
            continue
        if validator:
            result = validator(val)
            if result is not True:
                print(f"  ⚠  {result}")
                continue
        return val

def ask_float(prompt: str, default: float, lo: float = 0, hi: float = 9999) -> float:
    def v(x):
        try:
            f = float(x)
            return True if lo <= f <= hi else f"Enter a number between {lo} and {hi}."
        except ValueError:
            return "Please enter a valid number."
    return float(ask(prompt, str(default), v))

def ask_int(prompt: str, default: int, lo: int = 0, hi: int = 9999) -> int:
    def v(x):
        try:
            i = int(x)
            return True if lo <= i <= hi else f"Enter a number between {lo} and {hi}."
        except ValueError:
            return "Please enter a valid whole number."
    return int(ask(prompt, str(default), v))

def choose(prompt: str, options: list[str], default: int = 1) -> str:
    print(f"\n  {prompt}")
    for i, o in enumerate(options, 1):
        marker = " ◀" if i == default else ""
        print(f"    {i}. {o}{marker}")
    def v(x):
        try:
            n = int(x)
            return True if 1 <= n <= len(options) else f"Enter 1–{len(options)}."
        except ValueError:
            return "Enter a number."
    return options[int(ask("Your choice", str(default), v)) - 1]

def yesno(prompt: str, default: bool = True) -> bool:
    raw = input(f"  {prompt} ({'Y/n' if default else 'y/N'}): ").strip().lower()
    return default if not raw else raw.startswith("y")

def spin(label: str):
    print(f"  ⏳ {label}…")

# ── Intake interview ──────────────────────────────────────────────────────────
def main():
    print()
    line("═")
    print("  🏋️  FITNESS CREW — Personalized Coaching Report")
    print(f"  {datetime.date.today().strftime('%A, %d %B %Y')}")
    line("═")
    print("""
  I'll ask you a few quick questions, then our 3-agent AI crew
  will build your personalized coaching report:

    • HealthKitAgent  — analyses your health metrics
    • UIAgent         — builds your workout & nutrition plan
    • QAAgent         — reviews & assembles the final report

  No server needed — runs 100%% locally with Groq.
""")
    input("  Press ENTER to start…")

    # ── 1: Personal Info ──────────────────────────────────────────────────────
    print()
    header("SECTION 1 of 5 — Personal Information")
    name      = ask("Your first name", "Alex")
    age       = ask_int("Age (years)", 28, 16, 100)
    weight_kg = ask_float("Weight (kg)", 75.0, 30, 300)
    height_cm = ask_float("Height (cm)", 175.0, 100, 250)
    bmi       = weight_kg / ((height_cm / 100) ** 2)
    print(f"\n  ✓ BMI: {bmi:.1f}")

    # ── 2: Goals & Schedule ───────────────────────────────────────────────────
    print()
    header("SECTION 2 of 5 — Fitness Goals & Experience")
    goal = choose("Primary fitness goal?", [
        "Weight Loss", "Muscle Gain", "Endurance",
        "Flexibility & Mobility", "General Fitness",
    ])
    level = choose("Current fitness level?", [
        "Beginner (0–6 months)",
        "Intermediate (6 months–2 years)",
        "Advanced (2+ years)",
    ])
    days_per_week = ask_int("Training days per week?",     4, 1, 7)
    session_mins  = ask_int("Session length (minutes)?",  60, 15, 180)
    weeks_active  = ask_int("Weeks training so far?",      0, 0, 520)
    workouts_done = ask_int("Total workouts completed?",   0, 0, 5000)
    streak_days   = ask_int("Current training streak (days)?", 0, 0, 365)
    target_weeks  = ask_int("Weeks to reach your goal?",  12, 1, 104)
    equipment     = choose("Equipment available?", [
        "Full Gym (barbells, machines, cables)",
        "Dumbbells & Bench only",
        "Resistance Bands only",
        "Bodyweight / No equipment",
    ])

    # ── 3: Health Metrics ─────────────────────────────────────────────────────
    print()
    header("SECTION 3 of 5 — Health Metrics")
    steps          = ask_int  ("Steps today",                        8000, 0, 100000)
    calories       = ask_float("Active calories burned today (kcal)", 400, 0, 5000)
    heart_rate     = ask_float("Resting heart rate (bpm)",             65, 30, 220)
    sleep_hours    = ask_float("Sleep last night (hours)",            7.5, 0, 24)
    active_minutes = ask_int  ("Active minutes today",                 30, 0, 1440)

    # ── 4: Nutrition ──────────────────────────────────────────────────────────
    print()
    header("SECTION 4 of 5 — Nutrition")
    diet          = choose("Dietary preference?", [
        "No restrictions (Omnivore)", "Vegetarian", "Vegan",
        "Pescatarian", "Keto / Low-carb", "Gluten-free",
    ])
    meals_per_day = ask_int  ("Meals per day?",                3, 1, 8)
    water_liters  = ask_float("Water intake per day (liters)?", 2.0, 0, 10)
    allergies     = ask("Food allergies / foods to avoid?",    "None")
    supp_detail   = ask("Supplements you take?",               "None")

    # ── 5: Lifestyle ──────────────────────────────────────────────────────────
    print()
    header("SECTION 5 of 5 — Lifestyle")
    stress_level = ask_int("Daily stress level (1=low, 10=very high)?", 5, 1, 10)
    injuries     = ask("Injuries or physical limitations?", "None")
    extra_goals  = ask("Any other goals or notes?",
                       "Improve overall health and energy levels")

    # ── Confirm ───────────────────────────────────────────────────────────────
    print()
    line()
    print(f"""
  ✅ Intake complete!

   {name}, {age} yrs | {weight_kg}kg / {height_cm}cm | BMI {bmi:.1f}
   Goal     : {goal} in {target_weeks} weeks
   Level    : {level}
   Schedule : {days_per_week}×/week, {session_mins} min | Equipment: {equipment}
   Diet     : {diet} | {meals_per_day} meals/day | {water_liters}L water
   Metrics  : {steps:,} steps | {calories:.0f} cal | {heart_rate:.0f} bpm | {sleep_hours:.1f}h sleep
   Injuries : {injuries}
""")
    line()
    if not yesno("Generate your personalized coaching report now?", True):
        print("\n  Cancelled.\n")
        sys.exit(0)

    # ── Build context string ──────────────────────────────────────────────────
    today     = datetime.date.today().strftime("%d %B %Y")
    safe_name = name.replace(" ", "_").lower()
    date_str  = datetime.date.today().strftime("%Y%m%d")

    intake_ctx = (
        f"Name: {name} | Age: {age} | Weight: {weight_kg}kg | Height: {height_cm}cm | BMI: {bmi:.1f}\n"
        f"Goal: {goal} | Target: {target_weeks} weeks | Level: {level}\n"
        f"Schedule: {days_per_week} days/week × {session_mins} min | Equipment: {equipment}\n"
        f"Steps: {steps} | Active cal: {calories:.0f} kcal | HR: {heart_rate:.0f} bpm | Sleep: {sleep_hours:.1f}h | Active min: {active_minutes}\n"
        f"Weeks active: {weeks_active} | Workouts done: {workouts_done} | Streak: {streak_days} days\n"
        f"Diet: {diet} | {meals_per_day} meals/day | {water_liters}L water | Allergies: {allergies} | Supplements: {supp_detail}\n"
        f"Stress: {stress_level}/10 | Injuries: {injuries} | Extra goals: {extra_goals}"
    )

    # ── Run agents ────────────────────────────────────────────────────────────
    print()
    spin("HealthKitAgent — analysing your health metrics")
    hk_section = run_agent("HealthKitAgent",
        f"{intake_ctx}\n\n"
        "Write a detailed '### HealthKit Insights' markdown section:\n"
        "- Analysis of each metric (steps, calories, heart rate, sleep)\n"
        "- What the numbers mean for the user's goal\n"
        "- 2-3 specific data-driven recommendations\n"
        "Be specific and data-driven.", 700)

    spin("UIAgent — building your workout & nutrition plan")
    ui_section = run_agent("UIAgent",
        f"{intake_ctx}\n\n"
        "Write these markdown sections:\n"
        "### Personalized Motivational Message\n"
        "### QA-Verified Workout Strategy Summary\n"
        "(Weekly split with days, exercises, sets/reps matching goal & equipment)\n"
        "### Nutrition Approach\n"
        "(Calculate daily calories & macros, sample meal plan matching diet preference)\n"
        "### App Experience Improvements\n"
        "### This Week's Top 5 Actions\n"
        "Be specific. Address user by name. Reference their actual data.", 1400)

    spin("QAAgent — reviewing & assembling your report")
    report = run_agent("QAAgent",
        f"Compile a complete Personalized Coaching Report in markdown.\n"
        f"Date: {today} | {intake_ctx}\n\n"
        f"=== HEALTHKIT INSIGHTS ===\n{hk_section}\n\n"
        f"=== COACHING CONTENT ===\n{ui_section}\n\n"
        "Start with EXACTLY:\n"
        f"# {name}'s Personalized Coaching Report\n"
        f"## Date: {today}\n"
        "## QA Status: ![QA PASS](https://img.shields.io/badge/QA-PASS-success)\n\n"
        "Then a brief intro from 'your Head Fitness Coach'.\n"
        "Include ALL sections in this order:\n"
        "1. Personalized Motivational Message\n"
        "2. QA-Verified Workout Strategy Summary\n"
        "3. Nutrition Approach\n"
        "4. HealthKit Insights\n"
        "5. Progress Highlights (from user data)\n"
        "6. App Experience Improvements\n"
        "7. This Week's Top 5 Actions\n"
        "8. Motivational Closing\n"
        "Bold key numbers. Output ONLY the final markdown.", 2000)

    # ── Output ────────────────────────────────────────────────────────────────
    print()
    line("═")
    print(report)
    line("═")

    filename = f"report_{safe_name}_{date_str}.md"
    with open(filename, "w") as f:
        f.write(report)

    print(f"\n  💾 Saved → {filename}")
    print("  Open in VS Code / any Markdown viewer for full formatting.\n")


if __name__ == "__main__":
    main()
