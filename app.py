# The user wants to update their Flask app to perform real-time feature extraction from uploaded .wav files
# instead of relying on a preprocessed CSV file. This code will include extraction of MFCC, pitch, RMS, jitter, shimmer.

import os
from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import librosa
import parselmouth
import joblib
from parselmouth.praat import call
from tensorflow.keras.models import load_model
from tensorflow.keras.layers import Layer
import tensorflow.keras.backend as K
from waitress import serve
from app import app


app = Flask(__name__)
CORS(app) 

# Constants
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

WINDOW_SIZE_SECONDS = 2
SAMPLE_RATE = 22050
FEATURE_COLUMNS = [f"MFCC_{i}" for i in range(30)] + ["Pitch", "RMS", "Jitter", "Shimmer"]
LABEL_NAMES = ["Non-Fatigue", "Fatigue", "Ambiguous"]

# Custom Attention Layer for loading the model
class AttentionLayer(Layer):
    def __init__(self, **kwargs):
        super(AttentionLayer, self).__init__(**kwargs)

    def build(self, input_shape):
        self.W = self.add_weight(name="att_weight", shape=(input_shape[-1], 1), initializer="normal")
        self.b = self.add_weight(name="att_bias", shape=(input_shape[1], 1), initializer="zeros")
        super(AttentionLayer, self).build(input_shape)

    def call(self, x):
        e = K.tanh(K.dot(x, self.W) + self.b)
        a = K.softmax(e, axis=1)
        output = x * a
        return K.sum(output, axis=1)

# Load model and scaler
model = load_model("fatigue_bilstm_attention.h5", custom_objects={'AttentionLayer': AttentionLayer})
scaler = joblib.load("scaler.pkl")

def extract_features_from_wav(file_path):
    print(f"🎧 Extracting features from audio: {file_path}")
    try:
        y, sr = librosa.load(file_path, sr=SAMPLE_RATE)
        frame_length = WINDOW_SIZE_SECONDS * sr
        total_frames = len(y) // frame_length

        feature_list = []

        for i in range(total_frames):
            start = i * frame_length
            end = start + frame_length
            y_frame = y[start:end]

            if len(y_frame) < frame_length:
                continue  # skip if frame is too short

            # MFCCs
            mfcc = librosa.feature.mfcc(y=y_frame, sr=sr, n_mfcc=30)
            mfcc_mean = np.mean(mfcc, axis=1)

            # RMS
            rms = np.mean(librosa.feature.rms(y=y_frame))

            # Pitch, Jitter, Shimmer from Praat via parselmouth
            snd = parselmouth.Sound(y_frame, sampling_frequency=sr)
            pitch = snd.to_pitch()
            mean_pitch = call(pitch, "Get mean", 0, 0, "Hertz")
            point_process = call(snd, "To PointProcess (periodic, cc)", 75, 500)
            jitter = call(point_process, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3)
            shimmer = call([snd, point_process], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6)

            features = np.concatenate([mfcc_mean, [mean_pitch, rms, jitter, shimmer]])
            feature_list.append(features)

        X = np.array(feature_list)
        if X.shape[0] < WINDOW_SIZE_SECONDS:
            print("🚫 Not enough frames for one window.")
            return None

        X_scaled = scaler.transform(X)

        # Reshape into windows of WINDOW_SIZE_SECONDS
        num_chunks = X_scaled.shape[0] // WINDOW_SIZE_SECONDS
        X_trimmed = X_scaled[:num_chunks * WINDOW_SIZE_SECONDS]
        X_windowed = X_trimmed.reshape((num_chunks, WINDOW_SIZE_SECONDS, len(FEATURE_COLUMNS)))

        print(f"✅ Feature shape: {X_windowed.shape}")
        return X_windowed

    except Exception as e:
        print(f"❌ Error during audio feature extraction: {e}")
        return None


@app.route('/predict', methods=['POST'])
def predict():
    print("🔔 Received POST request.")
    try:
        if 'file' not in request.files:
            return jsonify({"error": "No file part in the request."}), 400

        file = request.files['file']
        if file.filename == '':
            return jsonify({"error": "No file selected."}), 400

        file_path = os.path.join(UPLOAD_FOLDER, file.filename)
        file.save(file_path)
        print(f"✅ File saved to {file_path}")

        features = extract_features_from_wav(file_path)

        if features is None or len(features) == 0:
            return jsonify({"error": "Failed to extract features."}), 400

        y_pred_probs = model.predict(features)
        y_pred_classes = np.argmax(y_pred_probs, axis=1)

        results = []
        for i, label_index in enumerate(y_pred_classes):
            results.append({
                "start_time": f"{i * WINDOW_SIZE_SECONDS}s",
                "end_time": f"{(i + 1) * WINDOW_SIZE_SECONDS}s",
                "label": LABEL_NAMES[label_index]
            })

        print(f"📊 Prediction results: {results}")
        return jsonify({"predictions": results})

    except Exception as e:
        print(f"❌ Internal error: {e}")
        return jsonify({"error": "Internal Server Error", "details": str(e)}), 500

if __name__ == "__main__":
    serve(app, host='0.0.0.0', port=5000)
