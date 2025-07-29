#!/bin/bash

# === CONFIGURATION ===
PROJECT_DIR="/media/edgeforestry/"
BACKEND_SCRIPT="backend/main.py"
PYTHON_ENV="$PROJECT_DIR/venv"
FLUTTER_CMD="/home/edgeforestry/flutter/bin/flutter"
CHROME_PATH="/usr/bin/chromium-browser"
DISPLAY_NUMBER=":0"
BACKEND_PORT=5001

# === STARTUP SEQUENCE ===

echo "[+] Starting app..."
cd "$PROJECT_DIR" || {
    echo "[-] Failed to cd into $PROJECT_DIR"
    exit 1
}

# Activate virtual environment
if [ -d "$PYTHON_ENV" ]; then
    echo "[+] Activating virtual environment"
    source "$PYTHON_ENV/bin/activate"
else
    echo "[!] No virtual environment found, using system Python"
fi

export CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
nohup python3 backend/main.py > backend.log 2>&1 &

# Wait for backend on port 5001 (your API)
while ! nc -z localhost 5001; do
  sleep 0.5
done

echo "[+] Backend is up"
cd /media/edgeforestry/rasp-pi-flutter-app/frontend || exit 1
nohup flutter run -d chrome --release --web-port=8080 > flutter.log 2>&1 &

echo "[✓] App started successfully"
