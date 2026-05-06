import base64
import uuid
import os
from locust import HttpUser, task, between

# Load and encode test image once at module level to avoid re-reading on every request
IMAGE_PATH = os.path.join(os.path.dirname(__file__), "test_image.jpeg")
with open(IMAGE_PATH, "rb") as f:
    IMAGE_B64 = base64.b64encode(f.read()).decode("utf-8")


class WildfireUser(HttpUser):
    wait_time = between(0.1, 0.5)  # seconds between tasks per user

    def on_start(self):
        self.client.headers.update({"Connection": "close"})

    @task(2)
    def predict(self):
        payload = {
            "uuid": str(uuid.uuid4()),
            "image": IMAGE_B64,
        }
        with self.client.post("/api/predict", json=payload, catch_response=True, timeout=30) as response:
            if response.status_code == 200:
                data = response.json()
                if "count" in data and "boxes" in data:
                    response.success()
                else:
                    response.failure(f"Unexpected response: {data}")
            else:
                response.failure(f"HTTP {response.status_code}: {response.text}")

    @task(1)
    def annotate(self):
        payload = {
            "uuid": str(uuid.uuid4()),
            "image": IMAGE_B64,
        }
        with self.client.post("/api/annotate", json=payload, catch_response=True, timeout=30) as response:
            if response.status_code == 200:
                data = response.json()
                if "image" in data:
                    response.success()
                else:
                    response.failure(f"Unexpected response: {data}")
            else:
                response.failure(f"HTTP {response.status_code}: {response.text}")
