import base64
import asyncio
import logging
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

import torch
import cv2
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from ultralytics import YOLO

torch.set_num_threads(1)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MODEL_PATH = "wildfire-detection/fire-models/fire_m.pt"
model: YOLO = None
executor = ThreadPoolExecutor(max_workers=2)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load model when FastAPI is activated
    global model
    model = YOLO(MODEL_PATH, task="detect")
    yield  # Handle all the requests here
    executor.shutdown(wait=True)  # Wait for in-flight inference to finish before exit


app = FastAPI(title="CloudEco Wildfire Detection", lifespan=lifespan)

# BaseModel: automatically parse the incoming data type base on the defined type hints
class InferenceRequest(BaseModel):
    uuid: str
    image: str  # base64-encoded image

MAX_INFER_SIZE = 640

def _decode_image(image_b64: str) -> np.ndarray:
    image_bytes = base64.b64decode(image_b64)
    np_arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Failed to decode image")
    h, w = img.shape[:2]
    if max(h, w) > MAX_INFER_SIZE:
        scale = MAX_INFER_SIZE / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_LINEAR)
    return img

# predict the image
def _run_predict(image_b64: str) -> dict:
    img = _decode_image(image_b64)
    results = model.predict(img, device="cpu", verbose=False)
    result = results[0]

    boxes = result.boxes
    detections = []
    box_list = []

    for i in range(len(boxes)):
        cls_id = int(boxes.cls[i])
        label = model.names[cls_id]
        x1, y1, x2, y2 = boxes.xyxy[i].tolist()  # xyxy
        prob = float(boxes.conf[i])  # conf
        detections.append(label)
        box_list.append({
            "x": x1,
            "y": y1,
            "width": x2 - x1,
            "height": y2 - y1,
            "probability": prob,
        })

    speed = result.speed

    return {
        "count": len(detections),
        "detections": detections,
        "boxes": box_list,
        "speed_preprocess_ms": speed.get("preprocess", 0.0),
        "speed_inference_ms": speed.get("inference", 0.0),
        "speed_postprocess_ms": speed.get("postprocess", 0.0),
    }


def _run_annotate(image_b64: str) -> str:
    img = _decode_image(image_b64)
    results = model.predict(img, device="cpu", verbose=False)
    annotated = results[0].plot()
    _, buffer = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return base64.b64encode(buffer).decode("utf-8")


@app.post("/api/predict")
async def predict(request: InferenceRequest):
    try:
        # obtain the current event loop instance for the current thread
        loop = asyncio.get_running_loop()
        payload = await loop.run_in_executor(executor, _run_predict, request.image)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("predict failed")
        raise HTTPException(status_code=500, detail=str(e))

    return {"uuid": request.uuid, **payload}


@app.post("/api/annotate")
async def annotate(request: InferenceRequest):
    try:
        loop = asyncio.get_running_loop()
        annotated_b64 = await loop.run_in_executor(executor, _run_annotate, request.image)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("annotate failed")
        raise HTTPException(status_code=500, detail=str(e))

    return {"uuid": request.uuid, "image": annotated_b64}

@app.get("/")
def main():
    return {"Welcome!"}

@app.get("/health")
def health():
    return {"status": "ok"}
