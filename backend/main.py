from flask import Flask, jsonify
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
logging.basicConfig(level=logging.INFO)

DUMMY_IMAGE_FOLDER = "/Users/BlueNucleus/Downloads/OW test pictures"


# ======== Model Loading =========
MODEL_PATH = "oak_wilt_demo3.h5"
model = tf.keras.models.load_model(MODEL_PATH)

# ======== Disease Labels ========
DISEASE = "Oak Wilt"

# ======== USB Utilities =========
def find_usb_mount():
    media_dir = "/media/pi"  # Adjust for your system
    if not os.path.exists(media_dir):
        return None

    for sub in os.listdir(media_dir):
        usb_path = os.path.join(media_dir, sub)
        if os.path.ismount(usb_path):
            return usb_path
    return None

def scan_usb_for_images(usb_path):
    valid_ext = [".jpg", ".jpeg", ".png", ".gif"]
    image_files = []
    for root, _, files in os.walk(usb_path):
        for file in files:
            if os.path.splitext(file)[-1].lower() in valid_ext:
                image_files.append(os.path.join(root, file))
    return image_files

# ======== Prediction =========
def predict_img(img):
    img_resized = cv2.resize(img, (256, 256))
    img_normalized = img_resized / 255.0
    img_expanded = np.expand_dims(img_normalized, axis=0)

    prediction = model.predict(img_expanded)
    return prediction[0][0]

# ======== GPS Extraction =========
def get_gps_data(image_path):
    try:
        with Image.open(image_path) as img:
            exif_data = img._getexif()
            if not exif_data:
                raise ValueError("No EXIF data")

            lat, lon = get_decimal_coordinates(exif_data)
            if lat is None or lon is None:
                raise ValueError("Invalid GPS data")

            return {'lat': lat, 'lon': lon}
    except Exception:
        # Return arbitrary/fake GPS coordinates for testing
        return {'lat': 42.9634, 'lon': -85.6681}  # Example: Grand Rapids, MI
    
def get_decimal_coordinates(info):
    for tag, value in info.items():
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
                lat = 0 - lat

            lon = convert_to_degrees(gps_lon)
            if gps_lon_ref != "E":
                lon = 0 - lon

            return lat, lon
    return None, None

def convert_to_degrees(value):
    d, m, s = value
    return d + (m / 60.0) + (s / 3600.0)

# ======== Result Writers =========
def write_csv(results, usb_path):
    csv_path = os.path.join(usb_path, "results.csv")
    pd.DataFrame(results).to_csv(csv_path, index=False)
    return csv_path

def write_geojson(results, usb_path):
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
    geojson_path = os.path.join(usb_path, "results.geojson")
    with open(geojson_path, "w") as f:
        json.dump({"type": "FeatureCollection", "features": geo_features}, f, indent=2)
    return geojson_path

# ======== Main Endpoint =========
@app.route("/scan-and-process", methods=["GET"])
def scan_and_process():
    usb_path = find_usb_mount()
    # if not usb_path:
    #     return jsonify({"error": "No USB drive found"}), 404
    if not usb_path:
        usb_path = DUMMY_IMAGE_FOLDER

    image_paths = scan_usb_for_images(usb_path)
    if not image_paths:
        return jsonify({"error": "No valid images found on USB"}), 404

    categories = {
        "THIS PICTURE HAS OAK WILT": [],
        "THERE'S A HIGH CHANCE OF OAK WILT": [],
        "POSSIBILITY OF OAK WILT": [],
        "DOES NOT HAVE OAK WILT": []
    }

    for path in image_paths:
        try:
            img = cv2.imread(path)
            prediction = predict_img(img) * 100
            gps = get_gps_data(path)
            filename = os.path.basename(path)

            if prediction > 99.5:
                category = "THIS PICTURE HAS OAK WILT"
            elif prediction > 90:
                category = "THERE'S A HIGH CHANCE OF OAK WILT"
            elif prediction > 70:
                category = "POSSIBILITY OF OAK WILT"
            else:
                category = "DOES NOT HAVE OAK WILT"

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

    combined = sum(categories.values(), [])
    
    output_path = usb_path
    csv_path = write_csv(combined, output_path)
    geojson_path = write_geojson(combined, output_path)

    # Send combined data as JSON for frontend to use directly
    return jsonify({
        "message": "Processing complete",
        "results_by_category": categories,
        "all_results": combined,
        "csv_saved_to": csv_path,
        "geojson_saved_to": geojson_path
    })

# ======== Run Server =========
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
