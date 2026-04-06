import base64
import asyncio
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

import cv2
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from ultralytics import YOLO

MODEL_PATH = "wildfire-detection/fire-models/fire_m.pt"
model: YOLO = None
executor = ThreadPoolExecutor()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    model = YOLO(MODEL_PATH)
    yield
    executor.shutdown(wait=False)


app = FastAPI(title="CloudEco Wildfire Detection", lifespan=lifespan)


class InferenceRequest(BaseModel):
    uuid: str
    image: str  # base64-encoded image


def _decode_image(image_b64: str) -> np.ndarray:
    image_bytes = base64.b64decode(image_b64)
    np_arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Failed to decode image")
    return img


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
        x1, y1, x2, y2 = boxes.xyxy[i].tolist()
        prob = float(boxes.conf[i])
        detections.append(label)
        box_list.append({
            "x": x1,
            "y": y1,
            "width": x2 - x1,
            "height": y2 - y1,
            "probability": prob,
        })

    speed = result.speed  # {"preprocess": ms, "inference": ms, "postprocess": ms}

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
    annotated = results[0].plot()  # BGR numpy array
    _, buffer = cv2.imencode(".jpg", annotated)
    return base64.b64encode(buffer).decode("utf-8")


@app.post("/api/predict")
async def predict(request: InferenceRequest):
    try:
        loop = asyncio.get_event_loop()
        payload = await loop.run_in_executor(executor, _run_predict, request.image)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"uuid": request.uuid, **payload}


@app.post("/api/annotate")
async def annotate(request: InferenceRequest):
    try:
        loop = asyncio.get_event_loop()
        annotated_b64 = await loop.run_in_executor(executor, _run_annotate, request.image)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"uuid": request.uuid, "image": annotated_b64}


@app.get("/health")
def health():
    return {"status": "ok"}
