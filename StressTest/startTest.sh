#!/bin/bash

# === CONFIGURATION ===
PROJECT_DIR="/home/edgeforestry/rasp-pi-flutter-app"
BACKEND_SCRIPT="/StressTest/testBackend/mainTest.py"  # Your Flask backend script
TEST_SETUP_SCRIPT="StressTest/images/fakeUsb.py"  # New setup script we'll create
PYTHON_ENV="$PROJECT_DIR/venv"
BACKEND_PORT=5002
FRONTEND_PORT=8000

# Fake USB configuration
NUM_TEST_IMAGES=50  # Reduced for faster startup
SAMPLE_IMAGE="$PROJECT_DIR/StressTest/images/sample.jpg"  # Path to your sample image

echo "[+] Starting Edge Forestry App with Fake USB Setup..."

# === CHANGE TO PROJECT DIRECTORY ===
cd "$PROJECT_DIR" || { echo "[-] Failed to cd into $PROJECT_DIR"; exit 1; }

# === ACTIVATE PYTHON ENVIRONMENT ===
if [ -d "$PYTHON_ENV" ]; then
    echo "[+] Activating virtual environment"
    source "$PYTHON_ENV/bin/activate"
else
    echo "[!] No virtual environment found — exiting."
    exit 1
fi

# === SETUP FAKE USB ===
echo "[+] Setting up fake USB with test images..."
if [ ! -f "$SAMPLE_IMAGE" ]; then
    echo "[!] Sample image not found at $SAMPLE_IMAGE"
    echo "[!] Please provide a sample.jpg file for testing"
    exit 1
fi 

# Run the fake USB setup
python3 "$PROJECT_DIR/$TEST_SETUP_SCRIPT"  
if [ $? -ne 0 ]; then
    echo "[-] Failed to setup fake USB — exiting."
    exit 1
fi

echo "[+] Fake USB setup complete"

# === KILL EXISTING PROCESSES ===
echo "[+] Cleaning up any existing processes..."
pkill -f "python3.*$PROJECT_DIR/$BACKEND_SCRIPT" 2>/dev/null || true
pkill -f "python3 -m http.server $FRONTEND_PORT" 2>/dev/null || true
pkill -f chromium-browser 2>/dev/null || true

# === START BACKEND ===
echo "[+] Starting Flask backend..."
if [ ! -f "$PROJECT_DIR/$BACKEND_SCRIPT" ]; then
    echo "[-] Backend script not found: $PROJECT_DIR/$BACKEND_SCRIPT"
    exit 1
fi

nohup python3 "$PROJECT_DIR/$BACKEND_SCRIPT" > backend.log 2>&1 &
BACKEND_PID=$!
echo "[+] Backend started with PID: $BACKEND_PID"

# === WAIT FOR BACKEND ===
echo "[+] Waiting for backend to initialize..."
TIMEOUT=30
COUNTER=0
while ! ss -tuln | grep -q ":$BACKEND_PORT " && [ $COUNTER -lt $TIMEOUT ]; do
    sleep 1
    COUNTER=$((COUNTER + 1))
    if [ $((COUNTER % 5)) -eq 0 ]; then
        echo "[+] Still waiting for backend... (${COUNTER}s)"
    fi
done

if [ $COUNTER -eq $TIMEOUT ]; then
    echo "[-] Backend failed to start within ${TIMEOUT} seconds"
    echo "[-] Check backend.log for errors:"
    tail -n 20 backend.log
    exit 1
fi

echo "[+] Backend is ready!"
 
# === START FRONTEND ===
echo "[+] Starting Flutter web frontend..."
FRONTEND_DIR="$PROJECT_DIR/frontend/build/web"
if [ ! -d "$FRONTEND_DIR" ]; then
    echo "[-] Frontend directory not found: $FRONTEND_DIR"
    echo "[!] Make sure to build the Flutter web app first:"
    echo "[!] cd $PROJECT_DIR/frontend && flutter build web"
    exit 1
fi

cd "$FRONTEND_DIR" || exit 1
nohup python3 -m http.server $FRONTEND_PORT > ../../http_server.log 2>&1 &
FRONTEND_PID=$!
echo "[+] Frontend started with PID: $FRONTEND_PID"

# === WAIT FOR FRONTEND ===
echo "[+] Waiting for frontend server..."
sleep 3

# Check if frontend is running
if ! ss -tuln | grep -q ":$FRONTEND_PORT "; then
    echo "[-] Frontend server failed to start"
    exit 1
fi

echo "[+] Frontend is ready at http://localhost:$FRONTEND_PORT"

# === CREATE CLEANUP SCRIPT ===
CLEANUP_SCRIPT="/tmp/cleanup_edge_forestry.sh"
cat > "$CLEANUP_SCRIPT" << EOF
#!/bin/bash
echo "Cleaning up Edge Forestry processes..."
kill $BACKEND_PID $FRONTEND_PID 2>/dev/null || true
pkill -f chromium-browser 2>/dev/null || true
echo "Cleanup complete."
EOF
chmod +x "$CLEANUP_SCRIPT"
echo "[+] Cleanup script created at $CLEANUP_SCRIPT"

# === START CHROMIUM ===
echo "[+] Starting Chromium in kiosk mode..."
sleep 2

# Set up display if needed
export DISPLAY=${DISPLAY:-:0}

# Start Chromium with better flags for Raspberry Pi
DISPLAY=:0 chromium-browser \
    --kiosk \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-backgrounding-occluded-windows \
    --disable-features=TranslateUI \
    --noerrdialogs \
    --disable-infobars \
    --disable-cache \
    --disable-application-cache \
    --disable-offline-load-stale-cache \
    --disk-cache-size=0 \
    --disable-extensions \
    "http://localhost:$FRONTEND_PORT" &

CHROMIUM_PID=$!
echo "[+] Chromium started with PID: $CHROMIUM_PID"

# === MONITOR AND KEEP ALIVE ===
echo "[✓] Edge Forestry App is running!"
echo ""
echo "=== STATUS ==="
echo "Backend:    http://localhost:$BACKEND_PORT (PID: $BACKEND_PID)"
echo "Frontend:   http://localhost:$FRONTEND_PORT (PID: $FRONTEND_PID)"
echo "Fake USB:   /media/edgeforestry/FAKE_USB ($NUM_TEST_IMAGES images)"
echo "Chromium:   Kiosk mode (PID: $CHROMIUM_PID)"
echo "Cleanup:    $CLEANUP_SCRIPT"
echo ""
echo "Press Ctrl+C to stop all services..."

# Function to cleanup on exit
cleanup() { 
    echo ""
    echo "[+] Shutting down services..."
    kill $BACKEND_PID $FRONTEND_PID $CHROMIUM_PID 2>/dev/null || true
    pkill -f chromium-browser 2>/dev/null || true
    echo "[+] Shutdown complete."
    exit 0
}

# Set trap to cleanup on script exit
trap cleanup INT TERM

# Wait for Chromium to exit (or until interrupted)
wait $CHROMIUM_PID 2>/dev/null || true

# If we get here, Chromium exited - cleanup other services
cleanup








