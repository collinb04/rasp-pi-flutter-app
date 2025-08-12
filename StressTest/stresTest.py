import os
import shutil
import time
import requests

# === CONFIG ===
NUM_IMAGES = 300               # number of test images
USB_MOUNT_PATH = "/media/edgeforestry/FAKE_USB"  # fake USB mount
SAMPLE_IMAGE = "sample.jpg"    # path to an example image
BACKEND_URL = "http://localhost:5002/scan-and-process"

# === SETUP FAKE USB ===
os.makedirs(USB_MOUNT_PATH, exist_ok=True)

# Clear existing files
for f in os.listdir(USB_MOUNT_PATH):
    os.remove(os.path.join(USB_MOUNT_PATH, f))

# Copy test images with fresh timestamps
for i in range(NUM_IMAGES):
    dest_file = os.path.join(USB_MOUNT_PATH, f"test_image_{i:03d}.jpg")
    shutil.copy(SAMPLE_IMAGE, dest_file)
    # Set modification time to "now"
    now = time.time()
    os.utime(dest_file, (now, now))

print(f"[+] Created {NUM_IMAGES} fresh images in {USB_MOUNT_PATH}")

# === RUN BACKEND TEST ===
print("[+] Sending scan-and-process request...")
r = requests.get(BACKEND_URL)

print(f"[+] Response status: {r.status_code}")
try:
    print(r.json())
except Exception:
    print(r.text)
print("[+] Test complete.")