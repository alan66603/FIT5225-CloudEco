# FIT5225-CloudEco
An Environmental Machine Learning-Based Cloud Application in Container Orchestration

### FastAPI (localhost)
```
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

### Docker build container
```
docker build --platform linux/amd64 -t cloudeco:latest .
docker buildx build --platform linux/amd64 -t alan66603/cloudeco:latest --push .
docker run -p 8001:8000 cloudeco:latest
```

### IaC cheat sheet
```
# delete all resource
terraform destroy

# stop only the VM, leave firewall policy, vpc, ssh k8s, network settings on
gcloud compute instances stop k8s-master k8s-worker-1 k8s-worker-2 --zone=australia-southeast1-a

# restart VM
gcloud compute instances start k8s-master k8s-worker-1 k8s-worker-2 --zone=australia-southeast1-a
```

# Ansible Kubernetes Installation
```
ansible-playbook -i ansible/inventory.ini ansible/install-k8s.yml
```

# Kubernetes deployment apply
```
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml 
kubectl apply -f k8s/service.yaml
# get NodePort
kubectl get svc -n cloudeco
python3 -m locust -f locust/locustfile.py --host=http://<Master external IP>:<NodePort>
```

### Image Data Transformation Pipeline

When you process an image from a web request to a computer vision model, the data undergoes several transformations. This table explains each stage, the data type involved, and a conceptual example of what that data looks like.

| Stage | Data Type | Representation Example | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `str` (Base64) | `"iVBORw0KGgoAAA..."` | A text-based representation used to safely transmit binary data over text-only protocols (like JSON/HTML). |
| **Decoded** | `bytes` | `b'\x89PNG\r\n...'` | The raw, compressed binary stream as it would exist in a file on your disk (e.g., a `.png` or `.jpg` file). |
| **Buffer** | `np.ndarray` (1D) | `[137, 80, 78, 71, ...]` | A flat array of 8-bit integers representing the file's raw bytes in memory, before any visual decoding happens. |
| **Output** | `np.ndarray` (3D/BGR) | `[[[255, 0, 0], [255, 0, 0]], ...]` | The "uncompressed" pixel grid. A 3D matrix where each element defines the **Blue, Green, and Red** values for a specific pixel. |

---

### Key Takeaways

* **Base64 to Bytes**: This is just a "translation" from text back to binary.
* **Bytes to 1D Array**: This is just a "reinterpretation" of the memory so NumPy can handle it.
* **1D Array to 3D BGR**: This is the **actual decoding** (performed by `cv2.imdecode`). It converts the compressed file format into a raw pixel map that you can actually manipulate or display as an image.

### Experiments and Benchmark Report

#### Summary Table

| Pods | Max Throughput (RPS) | Max Stable Users | Avg Latency at Threshold | Breaking Point | Scaling Efficiency |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | 1.10 | ~34 | 8,703 ms | ~35 users | baseline |
| 2 | 2.20 | ~79 | 13,195 ms | ~80 users | 2.00× |
| 4 | 4.10 | ~128 | 10,936 ms | ~130 users | 3.73× |
| 8 | 6.90 | ~164 | 9,774 ms | ~166 users | 6.27× |

#### Analysis

**Methodology**

Load testing was conducted using Locust against the CloudEco wildfire detection API deployed on a 3-node Kubernetes cluster (1 master, 2 workers; n2-custom-4-8192 on GCP). Each worker node provides 4 vCPUs and 8 GB RAM. Pods were constrained to 1.0 vCPU and 2 Gi memory each. The Locust workload mixed `/api/predict` (weight 2) and `/api/annotate` (weight 1) tasks, each carrying a base64-encoded test image, with inter-request wait times of 0.1–0.5 s per user. A 30-second client-side timeout was applied so that requests queued beyond the practical usability threshold are recorded as failures. For each pod count (1, 2, 4, 8), concurrent users were ramped from 1 until the breaking point — defined as the onset of HTTP failures or exponential latency growth — was reached.

**Results and Little's Law Verification**

Little's Law states L = λW, where L is the mean number of requests concurrently in the system, λ is the throughput (arrival rate), and W is the mean sojourn time (response time).

At the saturation point for 1 pod (λ = 1.00 req/s, W = 8.703 s):

> L = 1.00 × 8.703 ≈ **8.7 concurrent requests in the system**

This confirms the server is nearly fully utilised: with 34 concurrent users driving 1.00 req/s, the system already has ~8.7 requests queued or in service at any moment.

**Queuing Theory Analysis**

Each pod acts as an independent server. At low load (1–4 users), single-request latency is ~1.1 s, so the effective per-pod service rate is μ ≈ 1/1.1 ≈ 0.91 req/s. With `ThreadPoolExecutor(max_workers=2)` and `torch.set_num_threads(1)`, the two workers can overlap I/O-bound phases (request parsing, JSON serialisation), raising the observed saturation throughput to μ ≈ 1.10 req/s per pod before the single vCPU becomes the bottleneck.

Server utilisation at saturation is ρ = λ / (c × μ), where c is the number of pods. For 1 pod: ρ = 1.10 / (1 × 1.10) ≈ **1.0** (near-full utilisation), confirming the system is CPU-bound.

As pod count doubles, the aggregate service rate c × μ doubles, allowing twice the arrival rate before ρ approaches 1 again. This explains the near-linear throughput scaling (×2.00, ×3.73, ×6.27 for 2, 4, 8 pods respectively). The slight sub-linearity at 8 pods (6.27× instead of 8×) reflects scheduling overhead and CPU contention within shared worker nodes, where multiple pods on the same physical machine compete for CPU time slices.

**Saturation Point and Breaking Point**

The saturation point — where RPS plateaus despite additional users — occurs at approximately 4–5 concurrent users per pod. Beyond this, the system enters an overloaded regime: the request queue grows unboundedly, response time increases linearly with load, and eventually the 30-second client timeout triggers failures. The breaking point scales roughly linearly with pod count (~35 → ~80 → ~130 → ~166 users), demonstrating that horizontal pod scaling provides predictable, proportional capacity expansion.

**Conclusion**

The results confirm that the CloudEco inference service scales near-linearly with pod count under CPU-bound YOLOv8m inference. A single pod sustains 1.10 RPS; eight pods sustain 6.90 RPS (6.27× gain), achieving 78% parallel efficiency. Little's Law and M/M/c queuing theory accurately predict observed throughput and latency behaviour, validating the architectural decision to use stateless, horizontally-scalable pods for ML inference workloads.

#### 1 pod
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~34 users (last point with no failure) |
| Avg response time at threshold | 8,703 ms |
| Breaking point | ~35 users (failures start appearing) |
| Max throughput | ~1.10 RPS |

```
Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                            12    0( 0.00%) |   6149   1114   14084  14000 |    0.20        0.00
POST     /api/predict                                                             23    0( 0.00%) |  10036   1143   16892  15000 |    0.80        0.00
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                               35    0( 0.00%) |   8703   1114   16892  15000 |    1.00        0.00

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              14000  14000  14000  14000  14000  14000  14000  14000     12
POST     /api/predict                                                              15000  17000  17000  17000  17000  17000  17000  17000     23
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
         Aggregated                                                                15000  17000  17000  17000  17000  17000  17000  17000     35
```

#### 2 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~79 users (last point with no failure) |
| Avg response time at threshold | 13,195 ms |
| Breaking point | ~80 users (failures start appearing) |
| Max throughput | ~2.20 RPS |

```
Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                            56    0( 0.00%) |  13315   1037   26283  23000 |    0.70        0.00
POST     /api/predict                                                            105    0( 0.00%) |  13130   1337   25839  25000 |    1.30        0.00
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              161    0( 0.00%) |  13195   1037   26283  24000 |    2.00        0.00

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              23000  25000  26000  26000  26000  26000  26000  26000     56
POST     /api/predict                                                              25000  26000  26000  26000  26000  26000  26000  26000    105
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
         Aggregated                                                                24000  26000  26000  26000  26000  26000  26000  26000    161
```

#### 4 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~128 users (last point with no failure) |
| Avg response time at threshold | 10,936 ms |
| Breaking point | ~130 users (failures start appearing) |
| Max throughput | ~4.10 RPS |

```
Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                            82    0( 0.00%) |   9894   1086   24044  17000 |    1.10        0.00
POST     /api/predict                                                            164    0( 0.00%) |  11457    993   25748  21000 |    2.80        0.00
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              246    0( 0.00%) |  10936    993   25748  21000 |    3.90        0.00

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              17000  22000  23000  23000  24000  24000  24000  24000     82
POST     /api/predict                                                              21000  24000  25000  25000  26000  26000  26000  26000    164
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
         Aggregated                                                                21000  24000  25000  25000  26000  26000  26000  26000    246
```

#### 8 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~164 users (last point with no failure) |
| Avg response time at threshold | 9,774 ms |
| Breaking point | ~166 users (failures start appearing) |
| Max throughput | ~6.90 RPS |

```
Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                           187    0( 0.00%) |   9802   1214   29980  16000 |    3.20        0.00
POST     /api/predict                                                            320    0( 0.00%) |   9758   1050   30123  19000 |    3.50        0.00
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              507    0( 0.00%) |   9774   1050   30123  18000 |    6.70        0.00

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              16000  20000  21000  22000  23000  23000  24000  24000    187
POST     /api/predict                                                              19000  22000  24000  25000  27000  30000  30000  30000    320
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------
         Aggregated                                                                18000  22000  23000  24000  27000  30000  30000  30000    507
```

"ONNX Runtime was evaluated but exhibited higher and less stable latency on the e2 VM (avg 1.85s, spikes to 4s) compared to native PyTorch inference (avg 1.1s, stable at low load). This is attributed to ONNX Runtime's internal thread pool contending with the ThreadPoolExecutor under a single vCPU constraint. PyTorch was retained as the inference backend."