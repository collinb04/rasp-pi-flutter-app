import os
import shutil
import time 
import logging
from pathlib import Path
import sys

# === LOGGING SETUP ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# === CONFIG ===
NUM_IMAGES = 300               # number of test images
# Updated to match Flask backend expectations
USB_PARENT_PATH = "/home/edgeforestry"
USB_MOUNT_NAME = "FAKE_USB"
USB_MOUNT_PATH = os.path.join(USB_PARENT_PATH, USB_MOUNT_NAME)
SAMPLE_IMAGE = "/home/edgeforestry/rasp-pi-flutter-app/StressTest/images/sample.jpg"    # path to an example image
BACKEND_URL = "http://localhost:5001/scan-and-process"
REQUEST_TIMEOUT = 60           # increased timeout for processing 300 images

def create_mount_simulation():
    """Create a simulated mount point that the Flask backend will recognize."""
    try:
        # Create parent directory
        Path(USB_PARENT_PATH).mkdir(parents=True, exist_ok=True)
        
        # Create the "mount" directory
        Path(USB_MOUNT_PATH).mkdir(parents=True, exist_ok=True)
        
        # The Flask backend checks os.path.ismount(), which will return False
        # for regular directories. We need to modify the Flask backend or
        # work with what we have.
        logger.info(f"Created simulated mount structure at {USB_MOUNT_PATH}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to create mount simulation: {e}")
        return False

def setup_fake_usb():
    """Setup the fake USB environment with test images."""
    try:
        # Create mount simulation
        if not create_mount_simulation():
            return False

        # Clear existing files in the mount directory
        for f in Path(USB_MOUNT_PATH).iterdir():
            if f.is_file():
                f.unlink()
        logger.info("Cleared existing files")

        # Verify sample image exists
        if not Path(SAMPLE_IMAGE).exists():
            raise FileNotFoundError(f"Sample image not found: {SAMPLE_IMAGE}")

        # Copy test images with fresh timestamps
        now = time.time()
        for i in range(NUM_IMAGES):
            dest_file = Path(USB_MOUNT_PATH) / f"test_image_{i:03d}.jpg"
            shutil.copy(SAMPLE_IMAGE, dest_file)
            # Set modification time to recent time (within 48 hour window)
            # The Flask backend filters for images modified within 48 hours
            file_time = now - (i * 60)  # Each image 1 minute older than the last
            os.utime(dest_file, (file_time, file_time))

        logger.info(f"Created {NUM_IMAGES} fresh images in {USB_MOUNT_PATH}")
        
        # List first few files for verification
        files = list(Path(USB_MOUNT_PATH).glob("*.jpg"))
        logger.info(f"Sample files created: {[f.name for f in files[:5]]}")
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to setup fake USB: {e}")
        return False
 

def cleanup():
    """Optional cleanup function."""
    try:
        if Path(USB_MOUNT_PATH).exists():
            shutil.rmtree(USB_MOUNT_PATH)
            logger.info(f"Cleaned up {USB_MOUNT_PATH}")
    except Exception as e:
        logger.error(f"Cleanup failed: {e}")

def main():
    """Main test execution."""
    logger.info("=== OAK WILT DETECTION BACKEND TEST START ===")
    logger.info(f"Testing with {NUM_IMAGES} images")
    logger.info(f"USB simulation path: {USB_MOUNT_PATH}")
    logger.info(f"Backend URL: {BACKEND_URL}")
    
    # Setup phase
    if not setup_fake_usb():
        logger.error("Setup failed, aborting test")
        return False
  
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "cleanup":
        cleanup()
    else:
        success = main()
 