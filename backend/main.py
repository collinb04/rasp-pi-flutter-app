from flask import Flask, jsonify, send_file, request
from urllib.parse import unquote
import os
import cv2
import tensorflow as tf
import numpy as np
from PIL import Image
import PIL.ExifTags as ExifTags
import pandas as pd
import json
import logging
from flask_cors import CORS 

app = Flask(__name__)
CORS(app)

# Configure logging for production (errors only)
logging.basicConfig(level=logging.ERROR)

# Configuration
DUMMY_IMAGE_FOLDER = "/Users/BlueNucleus/Downloads/OW test pictures"
MODEL_PATH = "oak_wilt_demo3.h5"
DISEASE = "Oak Wilt"

# Global variables
image_path_map = {}
model = None

# ======== Model Loading =========
def load_model():
    global model
    try:
        model = tf.keras.models.load_model(MODEL_PATH)
    except Exception as e:
        logging.error(f"Failed to load model: {e}")
        raise

# Load model on startup
load_model()

# ======== USB Utilities =========
def find_usb_mount():
    """Find USB mount point on Raspberry Pi"""
    media_dir = "/media/pi"
    if not os.path.exists(media_dir):
        return None

    for sub in os.listdir(media_dir):
        usb_path = os.path.join(media_dir, sub)
        if os.path.ismount(usb_path):
            return usb_path
    return None

def scan_usb_for_images(usb_path):
    """Scan USB drive for valid image files"""
    valid_extensions = [".jpg", ".jpeg", ".png", ".gif"]
    image_files = []
    
    for root, _, files in os.walk(usb_path):
        for file in files:
            if os.path.splitext(file)[-1].lower() in valid_extensions:
                full_path = os.path.join(root, file)
                image_files.append(full_path)
                image_path_map[file] = full_path
    
    return image_files

# ======== Prediction =========
def predict_image(img):
    """Make prediction on image using loaded model"""
    try:
        img_resized = cv2.resize(img, (256, 256))
        img_normalized = img_resized / 255.0
        img_expanded = np.expand_dims(img_normalized, axis=0)
        
        prediction = model.predict(img_expanded, verbose=0)
        return prediction[0][0]
    except Exception as e:
        logging.error(f"Prediction failed: {e}")
        return 0.0

# ======== GPS Extraction =========
def get_gps_data(image_path):
    """Extract GPS coordinates from image EXIF data"""
    try:
        with Image.open(image_path) as img:
            exif_data = img._getexif()
            if not exif_data:
                return get_fallback_gps()

            lat, lon = get_decimal_coordinates(exif_data)
            if lat is None or lon is None:
                return get_fallback_gps()

            return {'lat': lat, 'lon': lon}
    except Exception:
        return get_fallback_gps()

def get_fallback_gps():
    """Return fallback GPS coordinates when real GPS data is unavailable"""
    return {'lat': 42.9634, 'lon': -85.6681}  # Grand Rapids, MI

def get_decimal_coordinates(exif_info):
    """Convert GPS EXIF data to decimal coordinates"""
    try:
        for tag, value in exif_info.items():
            decoded = ExifTags.TAGS.get(tag, tag)
            if decoded == 'GPSInfo':
                gps_data = {}
                for t in value:
                    sub_decoded = ExifTags.GPSTAGS.get(t, t)
                    gps_data[sub_decoded] = value[t]

                gps_lat = gps_data.get('GPSLatitude')
                gps_lat_ref = gps_data.get('GPSLatitudeRef')
                gps_lon = gps_data.get('GPSLongitude')
                gps_lon_ref = gps_data.get('GPSLongitudeRef')

                if not all([gps_lat, gps_lat_ref, gps_lon, gps_lon_ref]):
                    return None, None

                lat = convert_to_degrees(gps_lat)
                if gps_lat_ref != "N":
                    lat = -lat

                lon = convert_to_degrees(gps_lon)
                if gps_lon_ref != "E":
                    lon = -lon

                return lat, lon
    except Exception:
        pass
    return None, None

def convert_to_degrees(value):
    """Convert GPS coordinate to decimal degrees"""
    try:
        d, m, s = value
        return d + (m / 60.0) + (s / 3600.0)
    except Exception:
        return 0.0

# ======== Result Writers =========
def write_csv(results, output_path):
    """Write results to CSV file"""
    try:
        csv_path = os.path.join(output_path, "results.csv")
        pd.DataFrame(results).to_csv(csv_path, index=False)
        return csv_path
    except Exception as e:
        logging.error(f"Failed to write CSV: {e}")
        return None

def write_geojson(results, output_path):
    """Write results to GeoJSON file"""
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
        
        geojson_path = os.path.join(output_path, "results.geojson")
        with open(geojson_path, "w") as f:
            json.dump({"type": "FeatureCollection", "features": geo_features}, f, indent=2)
        return geojson_path
    except Exception as e:
        logging.error(f"Failed to write GeoJSON: {e}")
        return None

def classify_prediction(prediction_percent):
    """Classify prediction into categories based on percentage"""
    if prediction_percent > 99.5:
        return "THIS PICTURE HAS OAK WILT"
    elif prediction_percent > 90:
        return "THERE'S A HIGH CHANCE OF OAK WILT"
    elif prediction_percent > 70:
        return "POSSIBILITY OF OAK WILT"
    else:
        return "DOES NOT HAVE OAK WILT"

# ======== API Endpoints =========
@app.route("/scan-and-process", methods=["GET"])
def scan_and_process():
    """Main endpoint to scan USB and process images"""
    try:
        # Clear previous mappings
        global image_path_map
        image_path_map.clear()
        
        # Find USB or use dummy folder
        usb_path = find_usb_mount()
        if not usb_path:
            usb_path = DUMMY_IMAGE_FOLDER

        # Scan for images
        image_paths = scan_usb_for_images(usb_path)
        
        if not image_paths:
            return jsonify({"error": "No valid images found"}), 404

        # Initialize categories
        categories = {
            "THIS PICTURE HAS OAK WILT": [],
            "THERE'S A HIGH CHANCE OF OAK WILT": [],
            "POSSIBILITY OF OAK WILT": [],
            "DOES NOT HAVE OAK WILT": []
        }

        # Process each image
        for path in image_paths:
            try:
                img = cv2.imread(path)
                if img is None:
                    continue
                    
                prediction = predict_image(img) * 100
                gps = get_gps_data(path)
                filename = os.path.basename(path)
                category = classify_prediction(prediction)

                record = {
                    "filename": filename,
                    "prediction": f"{prediction:.2f}%",
                    "classification": category,
                    "latitude": gps["lat"],
                    "longitude": gps["lon"]
                }
                categories[category].append(record)
            except Exception as e:
                logging.error(f"Failed to process image {path}: {e}")
                continue

        # Combine all results
        combined = sum(categories.values(), [])
        
        # Write output files
        csv_path = write_csv(combined, usb_path)
        geojson_path = write_geojson(combined, usb_path)

        return jsonify({
            "message": "Processing complete",
            "results_by_category": categories,
            "all_results": combined,
            "csv_saved_to": csv_path,
            "geojson_saved_to": geojson_path
        })

    except Exception as e:
        logging.error(f"Error in scan-and-process: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/images/<path:filename>')
def get_image(filename):
    """Serve image files from USB drive"""
    try:
        decoded_filename = unquote(filename)
        
        # Try to get from mapping first
        if decoded_filename in image_path_map:
            full_path = image_path_map[decoded_filename]
            if os.path.exists(full_path):
                return send_file(full_path)
        
        # Try original filename in mapping
        if filename in image_path_map:
            full_path = image_path_map[filename]
            if os.path.exists(full_path):
                return send_file(full_path)
        
        # Fallback: search in USB path
        usb_path = find_usb_mount()
        if not usb_path:
            usb_path = DUMMY_IMAGE_FOLDER
        
        # Try direct path
        direct_path = os.path.join(usb_path, decoded_filename)
        if os.path.exists(direct_path):
            return send_file(direct_path)
        
        # Search recursively
        for root, _, files in os.walk(usb_path):
            if decoded_filename in files:
                file_path = os.path.join(root, decoded_filename)
                return send_file(file_path)
        
        return jsonify({"error": "Image not found"}), 404
        
    except Exception as e:
        logging.error(f"Error serving image {filename}: {e}")
        return jsonify({"error": "Error serving image"}), 500

@app.route('/get-image')
def get_image_simple():
    """Alternative endpoint for serving images via query parameter"""
    filename = request.args.get('name')
    if not filename:
        return jsonify({"error": "No filename provided"}), 400
    
    try:
        decoded_filename = unquote(filename)
        
        if decoded_filename in image_path_map:
            full_path = image_path_map[decoded_filename]
            if os.path.exists(full_path):
                return send_file(full_path)
        
        return jsonify({"error": "Image not found"}), 404
    except Exception as e:
        logging.error(f"Error in get-image: {e}")
        return jsonify({"error": "Error serving image"}), 500

@app.route('/list-images', methods=['GET'])
def list_images():
    """List available images for connection testing"""
    try:
        usb_path = find_usb_mount()
        if not usb_path:
            usb_path = DUMMY_IMAGE_FOLDER
        
        return jsonify({
            "usb_path": usb_path,
            "mapping_keys": list(image_path_map.keys()),
            "dummy_folder_exists": os.path.exists(DUMMY_IMAGE_FOLDER),
            "dummy_folder_contents": os.listdir(DUMMY_IMAGE_FOLDER) if os.path.exists(DUMMY_IMAGE_FOLDER) else []
        })
    except Exception as e:
        logging.error(f"Error listing images: {e}")
        return jsonify({"error": "Error listing images"}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

# ======== Run Server =========
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)