# FIT5225 Assignment 1 — CloudEco Wildfire Detection API

A containerised wildfire detection web service built with FastAPI and YOLOv8, deployed on a 3-node Kubernetes cluster on GCP.

**Publicly Accessible URL:** `http://34.40.252.167:30345`

> The cluster was deployed on GCP (australia-southeast1-a) and was live at submission time. The NodePort (30345) is fixed; only the master node's external IP changes if the VM is restarted. To redeploy, follow the IaC steps below.

---

## Architecture Overview

- **Cloud:** GCP, region `australia-southeast1-a`
- **Cluster:** 1 master + 2 worker nodes (`n2-custom-4-8192`: 4 vCPU, 8 GB RAM each)
- **Container:** Multi-stage Docker image with CPU-only PyTorch, non-root user
- **Pod resource limit:** 1.0 vCPU, 2 Gi memory per pod
- **Model:** YOLOv8m wildfire/fire detection (`fire_m.pt`)

---

## API Endpoints

### `POST /api/predict`
Accepts a base64-encoded image, returns detection results.

**Request:**
```json
{
  "uuid": "string",
  "image": "<base64-encoded image>"
}
```

**Response:**
```json
{
  "uuid": "string",
  "count": 2,
  "detections": ["fire", "smoke"],
  "boxes": [{"x": 10, "y": 20, "width": 50, "height": 60, "probability": 0.91}],
  "speed_preprocess_ms": 1.2,
  "speed_inference_ms": 850.4,
  "speed_postprocess_ms": 2.1
}
```

### `POST /api/annotate`
Accepts a base64-encoded image, returns an annotated image with bounding boxes drawn.

**Request:** Same as `/api/predict`

**Response:**
```json
{
  "uuid": "string",
  "image": "<base64-encoded annotated image>"
}
```

### `GET /health`
Returns `{"status": "ok"}` — used by Kubernetes readiness/liveness probes.

---

## Running Locally

**Prerequisites:** Python 3.12, pip

```bash
pip install torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

API will be available at `http://localhost:8000`.

---

## Docker

**Build and push:**
```bash
docker buildx build --platform linux/amd64 -t alan66603/cloudeco:latest --push .
```

**Run locally:**
```bash
docker run -p 8000:8000 alan66603/cloudeco:latest
```

---

## Infrastructure as Code (Terraform + Ansible)

### 1. Provision GCP VMs with Terraform

```bash
cd terraform
terraform init
terraform apply
```

This creates:
- A VPC network (`cloudeco-vpc`) and subnet (`10.0.0.0/24`)
- 1 master node and 2 worker nodes (`n2-custom-4-8192`) in `australia-southeast1-a`

To stop VMs without destroying infrastructure:
```bash
gcloud compute instances stop k8s-master k8s-worker-1 k8s-worker-2 --zone=australia-southeast1-a
```

To restart:
```bash
gcloud compute instances start k8s-master k8s-worker-1 k8s-worker-2 --zone=australia-southeast1-a
```

To destroy all resources:
```bash
terraform destroy
```

### 2. Install Kubernetes with Ansible

Update `ansible/inventory.ini` with current VM external IPs, then:

```bash
ansible-playbook -i ansible/inventory.ini ansible/install-k8s.yml
```

This installs Docker, cri-dockerd, kubeadm, kubelet, and kubectl on all nodes, then initialises the cluster.

---

## Kubernetes Deployment

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

**Scale pods:**
```bash
kubectl scale deployment cloudeco-deployment -n cloudeco --replicas=<N>
# N = 1, 2, 4, or 8
```

**Get the NodePort:**
```bash
kubectl get svc -n cloudeco
```

---

## Load Testing with Locust

```bash
pip install locust
python -m locust -f locust/locustfile.py --host=http://34.40.252.167:30345
# or
locust -f locust/locustfile.py \
  --host=http://34.40.252.167:30345 \
  --headless --users 30 --spawn-rate 1 --run-time 180s \
  --csv locust/results/1pod --csv-full-history
```

Open `http://localhost:8089` in your browser to start the test.

The script sends requests to both `/api/predict` (weight 2) and `/api/annotate` (weight 1) with a base64-encoded test image. Each virtual user waits 0.1–0.5 s between requests.

---

## Benchmark Results

Load testing was conducted on a 3-node GCP cluster. Each pod was limited to 1.0 vCPU and 2 Gi memory. Users were ramped until the first HTTP failure appeared (breaking point).

### Summary Table

| Pods | Max Stable Users | Avg Latency at Threshold | Max Throughput (RPS) | Scaling Efficiency |
|------|-----------------|--------------------------|----------------------|--------------------|
| 1    | ~34             | 8,703 ms                 | 1.10                 | 1.00×              |
| 2    | ~79             | 13,195 ms                | 2.20                 | 2.00×              |
| 4    | ~128            | 10,936 ms                | 4.10                 | 3.73×              |
| 8    | ~164            | 9,774 ms                 | 6.90                 | 6.27×              |

### Graphical Plots

See [`benchmark_plots.png`](benchmark_plots.png):
- **Left:** Average response time vs concurrent users (all pod configurations)
- **Right:** 95th percentile latency vs concurrent users (all pod configurations)

### Analysis

**Little's Law verification (1 pod):** At saturation (λ = 1.10 req/s, W = 8.703 s):
> L = λ × W = 1.10 × 8.703 ≈ **9.6 concurrent requests in flight**

This confirms near-full CPU utilisation at the breaking point.

**Queuing theory:** Each pod acts as an M/M/1-like server. The base per-pod service rate is μ ≈ 0.91 req/s (1/1.1 s per inference). With `ThreadPoolExecutor(max_workers=2)`, overlapping I/O phases raises effective throughput to ~1.10 RPS before the single vCPU becomes the hard bottleneck (ρ → 1).

**Horizontal scaling:** Throughput scales near-linearly with pod count (×2.00, ×3.73, ×6.27 for 2, 4, 8 pods). The 8-pod efficiency of 78% (6.27× vs theoretical 8×) reflects CPU contention between co-located pods on shared worker nodes.

**Bottleneck identification:** The primary bottleneck is CPU-bound YOLOv8m inference. ONNX Runtime was evaluated as an alternative but showed higher, less stable latency on this single-vCPU configuration (avg 1.85 s vs 1.1 s with PyTorch), likely due to internal thread-pool contention. PyTorch was retained.

---

## Generative AI Acknowledgement

Claude (Anthropic) was used to assist with the development of this project, including web service architecture design (`main.py`), Dockerfile optimisation, IaC scripting (Terraform and Ansible), and load testing script (`locust/locustfile.py`). All AI-generated outputs were reviewed, tested, and modified prior to use. Each source file contains inline comments identifying AI-generated sections and the modifications made.
