#!/bin/bash

PROJECT_DIR="/home/edgeforestry/rasp-pi-flutter-app"
BACKEND_SCRIPT="StressTest/mainTest.py"
PYTHON_ENV="$PROJECT_DIR/venv"
BACKEND_PORT=5002

echo "[+] Starting Edge Forestry App..."

cd "$PROJECT_DIR" || { echo "[-] Failed to cd into $PROJECT_DIR"; exit 1; }

if [ -d "$PYTHON_ENV" ]; then
    echo "[+] Activating virtual environment"
    source "$PYTHON_ENV/bin/activate"
else
    echo "[!] No virtual environment found — exiting."
    exit 1
fi

echo "[+] Starting backend..."
nohup python3 "$BACKEND_SCRIPT" > backend.log 2>&1 &

echo "[+] Waiting for backend to initialize..."
while ! ss -tuln | grep -q ':5002 '; do
    sleep 1
done

echo "[+] Serving Flutter web app..."

cd "$PROJECT_DIR/frontend/build/web" || exit 1
nohup python3 -m http.server 8000 > ../../http_server.log 2>&1 &

sleep 2

echo "[+] Starting Chromium in kiosk mode..."
DISPLAY=:0 exec chromium-browser --kiosk http://localhost:8000 --noerrdialogs --disable-infobars --no-sandbox --disable-cache

echo "[✓] App running in kiosk mode"








