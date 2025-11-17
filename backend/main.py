import os, sys, json, logging, threading, time
import cv2
from pathlib import Path
from typing import Tuple, Dict, Optional, List
from io import BytesIO
from urllib.parse import unquote
import torch, timm
import torchvision.transforms as T
import numpy as np
import pandas as pd
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory, send_file
from flask.logging import default_handler
from flask_cors import CORS
from PIL import Image, ExifTags
from werkzeug.utils import secure_filename
import torch.nn.init as init

# --- 1. Configuration & Setup ---
load_dotenv()
BASE_DIR = Path(__file__).resolve().parent

class Config:
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', 'http://localhost:8080').split(',')
    DESTINATION_PATH = BASE_DIR / os.getenv('DESTINATION_PATH', 'uploads')
    RESULTS_PATH = BASE_DIR / os.getenv('RESULTS_PATH', 'results')
    MODEL_PATH_OW = BASE_DIR / os.getenv('MODEL_PATH_OW', 'models/swinv2_tiny_oakwilt25.pth')
    MODEL_PATH_HWA = BASE_DIR / os.getenv('MODEL_PATH_HWA', 'models/FINAL_swin_tiny_model.pth')
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').upper()
    FLASK_RUN_HOST = os.getenv('FLASK_RUN_HOST', '127.0.0.1')
    FLASK_RUN_PORT = int(os.getenv('FLASK_RUN_PORT', 5001))

# create paths
Config.DESTINATION_PATH.mkdir(parents=True, exist_ok=True)
Config.RESULTS_PATH.mkdir(parents=True, exist_ok=True)

# Global variables
image_path_map = {}
model = None

# --- 2. Logging ---

class JsonFormatter(logging.Formatter):
    """Formats log records as a JSON string for CloudWatch."""

    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "funcName": record.funcName,
            "lineNo": record.lineno
        }
        # If there's exception info, add it to the log
        if record.exc_info:
            log_entry['exc_info'] = self.formatException(record.exc_info)
        return json.dumps(log_entry)


def setup_logging(app_instance):
    """Removes default Flask logger and sets up custom JSON logger."""
    # Remove the default handler
    app_instance.logger.removeHandler(default_handler)

    # Create a handler that writes to standard output
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    # Set the app's logger level and add the new handler
    logging.basicConfig(level=Config.LOG_LEVEL, handlers=[handler])
    app_instance.logger.setLevel(Config.LOG_LEVEL)

    # Quieten other loggers
    logging.getLogger('werkzeug').setLevel(logging.WARNING)

# --- 3. App init ---
app = Flask(__name__)
setup_logging(app)
CORS(app, origins=Config.CORS_ORIGINS, supports_credentials=True)

# --- 4. Globals & Model Cache ---
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

# Disease-specific configurations
DISEASE_CONFIGS = {
    "HWA": {
        "img_size": 224,
        "model_variants": [
            "swin_tiny_patch4_window7_224",
        ]
    },
    "Oak Wilt": {
        "img_size": 256,
        "model_variants": [
            "swinv2_tiny_window8_256",
            "swinv2_tiny_window16_256",
        ]
    }
}

device = "cuda" if torch.cuda.is_available() else "cpu"
model_cache: Dict[str, Tuple[torch.nn.Module, str]] = {}
model_lock = threading.Lock()  # protect model_cache during loads

def find_usb_mount() -> Path:
    """Find the first valid USB mount dynamically under /media or /mnt."""
    # Common USB mount roots
    mount_roots = [Path("/media/edgeforestry"), Path("/media/pi"), Path("/media"), Path("/mnt"), Path("/Volumes")]

    for root in mount_roots:
        if not root.exists():
            continue
        # Find any subdirectories (actual USB mount points)
        for subdir in root.iterdir():
            if subdir.is_dir():
                # Check if this subdirectory contains files or subfolders
                if any(subdir.iterdir()):
                    print(f"[INFO] Detected USB mount at: {subdir}")
                    return subdir

    print("[ERROR] No USB mount found under any known path.")
    return None

def scan_usb_for_images(usb_path):
    """
    Scan USB for recent image files (last 48 hours), ignoring system files.
    Returns a list of the most recent 100 image paths.
    """
    valid_extensions = [".jpg", ".jpeg", ".png", ".gif"]
    image_files = []
    now = time.time()
    cutoff = now - (48 * 60 * 60)  # 48 hours ago

    for root, _, files in os.walk(usb_path):
        # skip hidden/system directories
        if '/.' in root or root.endswith('.Trashes'):
            continue

        for file in files:
            if file.startswith("._") or file.startswith('.'):
                continue
            ext = os.path.splitext(file)[-1].lower()
            if ext in valid_extensions:
                full_path = os.path.join(root, file)
                try:
                    mtime = os.path.getmtime(full_path)
                    if mtime >= cutoff:
                        image_files.append((mtime, full_path))
                except Exception as e:
                    logging.error(f"Error accessing file {full_path}: {e}")
                    continue

    # Sort and limit
    image_files.sort(reverse=True)
    recent_paths = [path for _, path in image_files[:100]]

    # Update image_path_map (global)
    global image_path_map
    for path in recent_paths:
        filename = os.path.basename(path)
        image_path_map[filename] = path

    print("---- FILES FOUND DURING SCAN ----")
    for mtime, path in image_files[:10]:  # show top 10 for debug
        print(f"{time.ctime(mtime)}: {path}")
    print("---------------------------------")

    return recent_paths
    
# --- 5. Helper functions ---

def get_transform_for_disease(disease: str):
    """Return disease-specific transform with correct IMG_SIZE."""
    config = DISEASE_CONFIGS.get(disease)
    if not config:
        raise ValueError(f"Unknown disease type: {disease}")
    
    img_size = config["img_size"]
    
    return T.Compose([
        T.Resize(img_size, interpolation=T.InterpolationMode.BICUBIC),
        T.CenterCrop(img_size),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])

def allowed_file(filename: Optional[str]) -> bool:
    if not filename:
        return False
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_model_path(disease: str) -> Path:
    """Return model path for disease."""
    if disease == "Oak Wilt":
        return Path(Config.MODEL_PATH_OW)
    elif disease == "HWA":
        return Path(Config.MODEL_PATH_HWA)
    else:
        raise ValueError(f"Unknown disease type: {disease}")
    
def get_label_mappings(disease: str) -> Tuple[Dict[int, str], Dict[str, int]]:
    """
    Returns consistent label mappings for each disease.
    Ensure indices match model training.
    """
    mappings = {
        "Oak Wilt": {
            0: "Environment",  # healthy
            1: "Sick",         # oak wilt
        },
        "HWA": {
            0: "Sick",         # adelgid
            1: "Environment",  # healthy
            2: "Dead"
        }
    }

    if disease not in mappings:
        raise ValueError(f"Unknown disease type: {disease}")

    ID2LABEL = mappings[disease]
    LABEL2ID = {v: k for k, v in ID2LABEL.items()}
    return ID2LABEL, LABEL2ID

# Helper: reinitialize missing weights to mimic pre-2.6 behavior
def reset_missing_weights(model: torch.nn.Module, missing_keys: list):
    for name, param in model.named_parameters():
        if name in missing_keys:
            if 'weight' in name:
                if param.dim() > 1:
                    init.kaiming_uniform_(param, a=math.sqrt(5))
                else:
                    init.zeros_(param)
            elif 'bias' in name:
                init.zeros_(param)

# Core model loader
def load_model(path: Path, disease: str, device: str = "cpu") -> Tuple[torch.nn.Module, str]:
    """
    Load a timm model for a disease from checkpoint.
    Fully compatible with PyTorch >=2.6 / timm >=0.9 and pre-2.6 checkpoints.
    """
    if not path.exists():
        raise FileNotFoundError(f"Model checkpoint not found at {path}")

    config = DISEASE_CONFIGS.get(disease)
    if not config:
        raise ValueError(f"Unknown disease type: {disease}")

    model_variants = config["model_variants"]

    # Load checkpoint safely from old PyTorch
    sd = torch.load(str(path), map_location=device, weights_only=False)
    if isinstance(sd, dict) and any(k in sd for k in ("model", "state_dict")):
        sd = sd.get("model", sd.get("state_dict", sd))

    num_classes = 3 if disease == "HWA" else 2
    last_err = None

    for variant in model_variants:
        try:
            # timm models: use weights=None to avoid default weight conflicts
            m = timm.create_model(
                variant,
                weights=None,       # critical for PyTorch 2.7 / timm ≥0.9
                num_classes=num_classes,
                in_chans=3
            )

            # Attempt strict load first
            try:
                m.load_state_dict(sd, strict=True)
            except RuntimeError:
                # fallback to non-strict and reset missing weights
                missing_keys, unexpected_keys = m.load_state_dict(sd, strict=False)
                if missing_keys:
                    reset_missing_weights(m, missing_keys)

            m.eval()
            m.to(device)
            return m, variant

        except Exception as e:
            last_err = e
            app.logger.debug(f"Failed to load variant {variant} for {disease}: {e}")
            continue

    raise RuntimeError(
        f"Failed to load model from {path} for {disease}. "
        f"Tried variants: {model_variants}. Last error: {last_err}"
    )

# Thread-safe caching wrapper
def get_or_load_model_for_disease(disease: str, device: str = "cpu") -> Tuple[torch.nn.Module, str]:
    """
    Load a model once per disease and cache it for future use.
    Thread-safe for concurrent USB processing.
    """
    with model_lock:
        if disease in model_cache:
            return model_cache[disease]

        path = get_model_path(disease)
        app.logger.info(f"Loading model for disease '{disease}' from {path} onto {device}")
        model, variant = load_model(path, disease, device)
        model_cache[disease] = (model, variant)
        return model_cache[disease]

def softmax_top1(logits: torch.Tensor) -> Tuple[int, float]:
    p = torch.softmax(logits, dim=-1)[0].detach().cpu().numpy()
    i = int(np.argmax(p))
    return i, float(p[i])

def predict_img_with_model(model: torch.nn.Module, img: np.ndarray, disease: str, device: str = "cpu") -> Tuple[int, float]:
    """Predict using the passed-in model with disease-specific preprocessing."""
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    
    # Get disease-specific transform
    tfm = get_transform_for_disease(disease)
    img_tensor = tfm(pil_img).unsqueeze(0).to(device)
    
    logits = model(img_tensor)
    return softmax_top1(logits)

# EXIF / GPS helpers remain the same...
def convert_to_degrees(value: Tuple[float, float, float]) -> float:
    d, m, s = value
    return d + (m / 60.0) + (s / 3600.0)

def get_decimal_coordinates(info: dict) -> Tuple[Optional[float], Optional[float]]:
    for tag, value in info.items():
        decoded = ExifTags.TAGS.get(tag, tag)
        if decoded == 'GPSInfo':
            gps_data = {ExifTags.GPSTAGS.get(t, t): value[t] for t in value}
            gps_lat = gps_data.get('GPSLatitude')
            gps_lat_ref = gps_data.get('GPSLatitudeRef')
            gps_lon = gps_data.get('GPSLongitude')
            gps_lon_ref = gps_data.get('GPSLongitudeRef')
            if all([gps_lat, gps_lat_ref, gps_lon, gps_lon_ref]):
                lat = convert_to_degrees(gps_lat)
                if gps_lat_ref != "N":
                    lat = -lat
                lon = convert_to_degrees(gps_lon)
                if gps_lon_ref != "E":
                    lon = -lon
                return lat, lon
    return None, None

def get_gps_data(image_path: Path) -> Dict[str, float]:
    try:
        with Image.open(image_path) as img:
            exif_data = img._getexif()
            if not exif_data:
                return {'lat': 42.9634, 'lon': -85.6681}
            lat, lon = get_decimal_coordinates(exif_data)
            if lat is not None and lon is not None:
                return {'lat': lat, 'lon': lon}
    except Exception as e:
        app.logger.warning(f"Could not extract GPS from {image_path}: {e}")
    return {'lat': 42.9634, 'lon': -85.6681}

# ======== Result Writers =========
def get_unique_path(directory, base_filename, extension):
    counter = 1
    file_path = os.path.join(directory, f"{base_filename}.{extension}")
    while os.path.exists(file_path):
        file_path = os.path.join(directory, f"{base_filename}_{counter}.{extension}")
        counter += 1
    return file_path
    
def write_csv(results, output_path):
    # Write results to CSV file
    try:
        csv_path = get_unique_path(output_path, "results", "csv")
        pd.DataFrame(results).to_csv(csv_path, index=False)
        return csv_path
    except Exception as e:
        logging.error(f"Failed to write CSV: {e}")
        return None

def write_geojson(results, output_path):
    # Write results to GeoJSON file
    try:
        geo_features = []
        for item in results:
            if item['latitude'] is not None and item['longitude'] is not None:
                geo_features.append({
                    "type": "Feature",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [item["longitude"], item["latitude"]],
                    },
                    "properties": {
                        "filename": item["filename"],
                        "prediction": item["prediction"],
                        "classification": item["classification"],
                    }
                })
        
        geojson_path = get_unique_path(output_path, "results", "geojson")
        with open(geojson_path, "w") as f:
            json.dump({"type": "FeatureCollection", "features": geo_features}, f, indent=2)
        return geojson_path
    except Exception as e:
        logging.error(f"Failed to write GeoJSON: {e}")
        return None

# --- 6. Routes ---
@app.route('/', methods=['GET'])
def greetings():
    return jsonify({
        "message": "Hello from Edge Forestry API (Flask)",
        "device": device,
        "available_models": {
            "Oak Wilt": str(Config.MODEL_PATH_OW),
            "HWA": str(Config.MODEL_PATH_HWA)
        }
    })

@app.route("/scan-and-process", methods=['GET', 'POST'])
def scan_and_process():
    BUILD_TIMESTAMP = 1762437299

    cutoff_period = 60 * 60 * 24 * 365 * 2.5  # 2.5 years in seconds

    if time.time() - BUILD_TIMESTAMP > cutoff_period:
        return jsonify({"message": "Software expired. Please contact support."}), 403

    try:
        print("\n=== [START] /scan-and-process ===")
        disease = request.args.get('disease')
        logging.info(f"Requested disease: {disease}")

        if not disease:
            print("[ERROR] Missing 'disease' parameter")
            return jsonify({"message": "Missing 'disease' parameter"}), 400
        print(f"[INFO] Processing USB images for disease: {disease}")

        # --- Load model ---
        try:
            model, model_name = get_or_load_model_for_disease(disease)
            print(f"[INFO] Loaded model '{model_name}' for disease '{disease}'")
        except Exception as e:
            print(f"[ERROR] Failed to load model for {disease}: {e}")
            return jsonify({"message": f"Model load failure: {e}"}), 500

        # --- Detect USB mount ---
        usb_mount = find_usb_mount()
        if usb_mount is None:
            return jsonify({"message": "No USB device found"}), 400

        print(f"[INFO] Searching for images in: {usb_mount}")
        print(f"[INFO] USB device found at: {usb_mount}")

        # --- Gather images ---
        image_files: List[Path] = []
        for ext in ("*.jpg", "*.jpeg", "*.png", "*.gif", "*.JPG"):
            image_files.extend(usb_mount.rglob(ext))

        if not image_files:
            print("[WARNING] No image files found on USB drive")
            return jsonify({"message": "No image files found on USB drive"}), 400

        print(f"[INFO] Found {len(image_files)} image(s) on USB")

        # --- Initialize result structure ---
        results = {
            f"THIS AREA DOES NOT HAVE {disease}": [],
            f"THIS AREA HAS {disease}": [],
            f"THERE'S A HIGH CHANCE OF {disease} IN THIS AREA": [],
            f"THERE'S A POSSIBILITY OF {disease} IN THIS AREA": [],
            f"THIS AREA DOES NOT HAVE {disease}": [],
            f"THIS AREA IS DEAD": [],
            f"THERE'S A HIGH CHANCE OF THIS AREA BEING DEAD": [],
            f"THERE'S A POSSIBILITY OF THIS AREA BEING DEAD": [],
            f"THERE IS LOW CONFIDENCE OF {disease} IN THIS AREA": []
        }

        # ensure image_path_map is updated for serving later
        global image_path_map
        valid_image_map = {}

        # --- Process each image ---
        for img_path in image_files:
            try:
                filename = img_path.name
                print(f"[INFO] Processing {filename}...")

                img = cv2.imread(str(img_path))
                if img is None:
                    print(f"[ERROR] cv2 failed to read image: {filename}")
                    continue

                class_idx, confidence = predict_img_with_model(model, img, disease, device=device)
                prediction_percent = confidence * 100.0

                ID2LABEL, LABEL2ID = get_label_mappings(disease)
                predicted_class = ID2LABEL.get(class_idx, "Unknown")

                # --- Categorize results ---
                category = "UNKNOWN CLASSIFICATION"
                description = ""

                if predicted_class == "Environment":
                    category = f"THIS AREA DOES NOT HAVE {disease}"
                    description = "This area appears healthy and shows no signs of disease."
                elif predicted_class == "Sick":
                    if prediction_percent > 99.5:
                        category = f"THIS AREA HAS {disease}"
                    elif prediction_percent > 90:
                        category = f"THERE'S A HIGH CHANCE OF {disease} IN THIS AREA"
                    elif prediction_percent > 70:
                        category = f"THERE'S A POSSIBILITY OF {disease} IN THIS AREA"
                    else:
                        category = f"THERE IS LOW CONFIDENCE OF {disease} IN THIS AREA"
                elif predicted_class == "Dead":
                    if prediction_percent > 99.5:
                        category = "THIS AREA IS DEAD"
                    elif prediction_percent > 90:
                        category = "THERE'S A HIGH CHANCE OF THIS AREA BEING DEAD"
                    elif prediction_percent > 70:
                        category = "THERE'S A POSSIBILITY OF THIS AREA BEING DEAD"
                    else:
                        category = f"THERE IS LOW CONFIDENCE OF {disease} IN THIS AREA"

                gps = get_gps_data(img_path)
                results[category].append({
                    "filename": filename,
                    "prediction": prediction_percent,
                    "predicted class": predicted_class,  # Changed: space instead of camelCase
                    "predictedClass": predicted_class,   # Keep both for compatibility
                    "classification": category,
                    "description": description,
                    "latitude": gps.get('lat'),
                    "longitude": gps.get('lon')
                })

                # map filename to absolute path so /images/<filename> can serve it later
                valid_image_map[filename] = str(img_path)

            except Exception as e:
                print(f"[ERROR] Error processing {img_path.name}: {e}")
                import traceback
                traceback.print_exc()
                continue

        # persist mapping for image serving endpoints
        image_path_map.update(valid_image_map)

        # --- Write CSV and GeoJSON ---
        print("[INFO] Writing results to CSV and GEOJSON...")
        filtered_results = [
            item for key, items in results.items()
            if "DOES NOT HAVE" not in key for item in items
        ]

        # ensure results dir exists
        Config.RESULTS_PATH.mkdir(parents=True, exist_ok=True)

        csv_file_path = Config.RESULTS_PATH / 'results.csv'
        geojson_file_path = Config.RESULTS_PATH / 'results.geojson'

        if filtered_results:
            pd.DataFrame(filtered_results).to_csv(csv_file_path, index=False)
            features = []
            for item in filtered_results:
                if item.get('latitude') is not None and item.get('longitude') is not None:
                    features.append({
                        "type": "Feature",
                        "properties": {k: v for k, v in item.items() if k not in ('latitude', 'longitude')},
                        "geometry": {"type": "Point", "coordinates": [item['longitude'], item['latitude']]}
                    })
            geojson = {"type": "FeatureCollection", "features": features}
            with open(geojson_file_path, 'w') as fh:
                json.dump(geojson, fh, indent=2)
        else:
            # write empty files to keep UX predictable
            pd.DataFrame(columns=[
                'filename', 'prediction', 'predicted class', 'classification',
                'description', 'latitude', 'longitude'
            ]).to_csv(csv_file_path, index=False)
            with open(geojson_file_path, 'w') as fh:
                json.dump({"type": "FeatureCollection", "features": []}, fh, indent=2)

        print(f"[SUCCESS] Results written successfully")
        print(f"[INFO] CSV: {csv_file_path}")
        print(f"[INFO] GEOJSON: {geojson_file_path}")

        # --- Flatten results for Flutter ---
        all_results = []
        for category, items in results.items():
            all_results.extend(items)

        response_data = {
            "message": "USB image processing complete",
            "all_results": all_results,  # ADDED: Flattened list for Flutter
            "results": results,           # KEPT: Original nested structure
            "csv_file_url": f"{request.host_url.rstrip('/')}/results/{csv_file_path.name}",
            "geojson_file_url": f"{request.host_url.rstrip('/')}/results/{geojson_file_path.name}",
            "model_used": model_name
        }

        print("=== [END] /scan-and-process ===\n")
        return jsonify(response_data)

    except Exception as e:
        print(f"[FATAL] Unhandled exception in /scan-and-process: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"message": "Internal server error"}), 500


@app.route('/results/<path:filename>')
def serve_result_file(filename):
    """Serve files from the results directory (CSV / GeoJSON)."""
    try:
        # send_from_directory expects a str path
        return send_from_directory(str(Config.RESULTS_PATH), filename, as_attachment=False)
    except Exception as e:
        app.logger.error(f"Error serving result file {filename}: {e}")
        return jsonify({"error": "Could not retrieve results file"}), 404

        
#Resizes images for optimal serving and rendering on frontend
def serve_resized_image(path):
    try:
        with Image.open(path) as img:
            # Resize while maintaining aspect ratio (e.g., max width 600px)
            img.thumbnail((600, 600))  # limits width or height to 600px
            img_io = BytesIO()
            img.save(img_io, format="JPEG", quality=70)
            img_io.seek(0)
            return send_file(img_io, mimetype='image/jpeg')
    except Exception as e:
        logging.error(f"Failed to resize image: {e}")
        return send_file(path)  # fallback to original image

@app.route('/images/<path:filename>')
def get_image(filename):
    # Serve image files from USB drive
    try:
        decoded_filename = unquote(filename)
        
        # Try to get from mapping first
        if decoded_filename in image_path_map:
            full_path = image_path_map[decoded_filename]
            if os.path.exists(full_path):
                return serve_resized_image(full_path)
        
        # Try original filename in mapping
        if filename in image_path_map:
            full_path = image_path_map[filename]
            if os.path.exists(full_path):
                return serve_resized_image(full_path)
        
        # Fallback: search in USB path
        usb_path = find_usb_mount()
        if not usb_path:
            return jsonify({"error": "No USB path found"}), 404
        
        # Try direct path
        direct_path = os.path.join(usb_path, decoded_filename)
        if os.path.exists(direct_path):
            return serve_resized_image(direct_path)
        
        # Search recursively
        for root, _, files in os.walk(usb_path):
            if decoded_filename in files:
                file_path = os.path.join(root, decoded_filename)
                return serve_resized_image(file_path)
        
        return jsonify({"error": "Image not found"}), 404
        
    except Exception as e:
        logging.error(f"Error serving image {filename}: {e}")
        return jsonify({"error": "Error serving image"}), 500

@app.route('/get-image')
def get_image_simple():
    # Alternative endpoint for serving images via query parameter
    filename = request.args.get('name')
    if not filename:
        return jsonify({"error": "No filename provided"}), 400
    
    try:
        decoded_filename = unquote(filename)
        
        if decoded_filename in image_path_map:
            full_path = image_path_map[decoded_filename]
            if os.path.exists(full_path):
                return serve_resized_image(full_path)
        
        return jsonify({"error": "Image not found"}), 404
    except Exception as e:
        logging.error(f"Error in get-image: {e}")
        return jsonify({"error": "Error serving image"}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

# --- 7. Run (dev only) ---
if __name__ == "__main__":
    app.logger.info(f"Starting Flask app on {Config.FLASK_RUN_HOST}:{Config.FLASK_RUN_PORT}")
    app.run(host=Config.FLASK_RUN_HOST, port=Config.FLASK_RUN_PORT, debug=False)
