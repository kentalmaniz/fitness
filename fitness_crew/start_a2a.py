"""
fitness_crew/start_a2a.py
─────────────────────────
Launcher for the full A2A fitness coaching stack.

Starts 3 A2A agent servers + 1 concierge in separate processes.
Ctrl+C shuts everything down cleanly.

Usage:  python3 start_a2a.py
"""
from __future__ import annotations

import os
import sys
import signal
import subprocess
import time
import urllib.request
import urllib.error

import crew_config as cfg

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENV_PYTHON = os.path.join(SCRIPT_DIR, ".venv", "bin", "python")
PYTHON = VENV_PYTHON if os.path.exists(VENV_PYTHON) else sys.executable

# Processes to launch (in order)
SERVERS = [
    {
        "name": "HealthKit Analyst",
        "script": "a2a_healthkit_server.py",
        "port": cfg.HEALTHKIT_AGENT_PORT,
        "emoji": "🫀",
    },
    {
        "name": "Fitness Coach",
        "script": "a2a_coach_server.py",
        "port": cfg.COACH_AGENT_PORT,
        "emoji": "💪",
    },
    {
        "name": "QA Reviewer",
        "script": "a2a_qa_server.py",
        "port": cfg.QA_AGENT_PORT,
        "emoji": "✅",
    },
]

CONCIERGE = {
    "name": "Fitness Concierge",
    "script": "a2a_concierge.py",
    "port": cfg.CONCIERGE_PORT,
    "emoji": "🏋️",
}

processes: list[subprocess.Popen] = []


def wait_for_server(port: int, timeout: float = 30.0) -> bool:
    """Wait until a server responds on the given port."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            req = urllib.request.Request(
                f"http://localhost:{port}/.well-known/agent.json",
                method="GET",
            )
            with urllib.request.urlopen(req, timeout=2):
                return True
        except (urllib.error.URLError, ConnectionError, OSError):
            time.sleep(0.5)
    return False


def shutdown(_sig=None, _frame=None):
    """Terminate all child processes."""
    print("\n\n🛑 Shutting down A2A stack…")
    for p in reversed(processes):
        try:
            p.terminate()
            p.wait(timeout=5)
        except Exception:
            p.kill()
    print("   All processes stopped.\n")
    sys.exit(0)


def main():
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    width = 60
    print()
    print("═" * width)
    print("  🏋️  FITNESS CREW — A2A Protocol Stack")
    print("═" * width)
    print()
    print("  Architecture:")
    print("  ┌─────────────────────────────────────────┐")
    print("  │  iOS App  ──→  Concierge (A2A Client)   │")
    print("  │                  ↓  ↓  ↓                │")
    print("  │         ┌───────┼──┼──┼───────┐         │")
    print("  │         │  HK   │ Coach │  QA  │         │")
    print("  │         │ :8001 │ :8002 │ :8003│         │")
    print("  │         └───────┴───────┴──────┘         │")
    print("  │              A2A Servers                 │")
    print("  └─────────────────────────────────────────┘")
    print()

    # ── Start A2A servers ─────────────────────────────────────────────────────
    for srv in SERVERS:
        script_path = os.path.join(SCRIPT_DIR, srv["script"])
        print(f"  {srv['emoji']} Starting {srv['name']} on port {srv['port']}…")
        p = subprocess.Popen(
            [PYTHON, script_path],
            cwd=SCRIPT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        processes.append(p)

    # Wait for all agent servers to be ready
    print()
    for srv in SERVERS:
        port = srv["port"]
        ok = wait_for_server(port, timeout=30)
        if ok:
            print(f"  ✅ {srv['name']} ready at http://localhost:{port}")
            print(f"     Agent Card: http://localhost:{port}/.well-known/agent.json")
        else:
            print(f"  ❌ {srv['name']} failed to start on port {port}")
            shutdown()

    # ── Start Concierge ───────────────────────────────────────────────────────
    print()
    script_path = os.path.join(SCRIPT_DIR, CONCIERGE["script"])
    print(f"  {CONCIERGE['emoji']} Starting {CONCIERGE['name']} on port {CONCIERGE['port']}…")
    p = subprocess.Popen(
        [PYTHON, script_path],
        cwd=SCRIPT_DIR,
    )
    processes.append(p)

    # Wait for concierge health
    time.sleep(3)

    print()
    print("─" * width)
    print()
    print("  🚀 A2A Stack is LIVE!")
    print()
    print(f"  Concierge API:  http://localhost:{CONCIERGE['port']}")
    print(f"  Health check:   http://localhost:{CONCIERGE['port']}/health")
    print(f"  Agent list:     http://localhost:{CONCIERGE['port']}/agents")
    print()
    print("  Agent Cards:")
    for srv in SERVERS:
        print(f"    {srv['emoji']} http://localhost:{srv['port']}/.well-known/agent.json")
    print()
    print("  iOS app → same endpoints at http://localhost:8000")
    print("    POST /chat      — 3-agent Q&A via A2A")
    print("    POST /motivate  — daily motivation via A2A")
    print("    POST /report    — full coaching report via A2A")
    print()
    print("  Press Ctrl+C to stop all services.")
    print()
    print("─" * width)

    # Keep running until interrupted
    try:
        for p in processes:
            p.wait()
    except KeyboardInterrupt:
        shutdown()


if __name__ == "__main__":
    main()
