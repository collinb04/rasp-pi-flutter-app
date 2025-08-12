import os
import shutil
import time
import requests
import logging
from pathlib import Path

# === LOGGING SETUP ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# === CONFIG ===
NUM_IMAGES = 300               # number of test images
# Updated to match Flask backend expectations
USB_PARENT_PATH = "/home/edgeforestry"
USB_MOUNT_NAME = "FAKE_USB"
USB_MOUNT_PATH = os.path.join(USB_PARENT_PATH, USB_MOUNT_NAME)
SAMPLE_IMAGE = "sample.jpg"    # path to an example image
BACKEND_URL = "http://localhost:5002/scan-and-process"
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

def test_backend():
    """Test the backend scan-and-process endpoint."""
    try:
        logger.info("Sending scan-and-process request...")
        logger.info(f"Backend will look for USB mounts in: {USB_PARENT_PATH}")
        
        start_time = time.time()
        
        response = requests.get(BACKEND_URL, timeout=REQUEST_TIMEOUT)
        
        duration = time.time() - start_time
        logger.info(f"Request completed in {duration:.2f} seconds")
        logger.info(f"Response status: {response.status_code}")
        
        # Handle response content
        try:
            json_response = response.json()
            logger.info("Response (JSON):")
            
            # Print summary information
            if "results_by_category" in json_response:
                categories = json_response["results_by_category"]
                for category, results in categories.items():
                    logger.info(f"  {category}: {len(results)} images")
            
            if "all_results" in json_response:
                total_processed = len(json_response["all_results"])
                logger.info(f"Total images processed: {total_processed}")
                
            # Print first few results as examples
            if "all_results" in json_response and json_response["all_results"]:
                logger.info("First few results:")
                for result in json_response["all_results"][:3]:
                    logger.info(f"  {result['filename']}: {result['prediction']} - {result['classification']}")
                    
            return json_response
            
        except ValueError:
            logger.info("Response (Text):")
            print(response.text)
            return response.text
            
    except requests.exceptions.Timeout:
        logger.error(f"Request timed out after {REQUEST_TIMEOUT} seconds")
        logger.error("Try increasing REQUEST_TIMEOUT or reducing NUM_IMAGES")
        return None
    except requests.exceptions.ConnectionError:
        logger.error(f"Failed to connect to {BACKEND_URL}")
        logger.error("Make sure the Flask backend is running on port 5002")
        return None
    except Exception as e:
        logger.error(f"Unexpected error during backend test: {e}")
        return None

def verify_output_files():
    """Check if the backend created output files."""
    try:
        csv_files = list(Path(USB_MOUNT_PATH).glob("results*.csv"))
        geojson_files = list(Path(USB_MOUNT_PATH).glob("results*.geojson"))
        
        logger.info(f"CSV files created: {len(csv_files)}")
        logger.info(f"GeoJSON files created: {len(geojson_files)}")
        
        for csv_file in csv_files:
            logger.info(f"  CSV: {csv_file}")
        for geojson_file in geojson_files:
            logger.info(f"  GeoJSON: {geojson_file}")
            
    except Exception as e:
        logger.error(f"Error checking output files: {e}")

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
    
    # Test phase
    result = test_backend()
    
    # Check output files
    if result:
        verify_output_files()
    
    # Summary
    if result is not None:
        logger.info("=== TEST COMPLETED SUCCESSFULLY ===")
        return True
    else:
        logger.error("=== TEST FAILED ===")
        return False

if __name__ == "__main__":
    success = main()
    
    # Uncomment the next line if you want to clean up after testing
    cleanup()
    
    exit(0 if success else 1)