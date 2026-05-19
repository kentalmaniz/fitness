#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${GROQ_API_KEY:-}" ]]; then
  cat <<'EOF'
GROQ_API_KEY is not set.

Run this first, replacing the value with your Groq key:
  export GROQ_API_KEY='gsk_your_key_here'

Then start the server again:
  ./run_server.sh
EOF
  exit 1
fi

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi

source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

echo "Starting Fitness Crew server at http://0.0.0.0:8000"
echo "Simulator URL: http://localhost:8000"
echo "Real iPhone URL: use your Mac's Wi-Fi IP, e.g. http://192.168.1.23:8000"
python crew_server.py
