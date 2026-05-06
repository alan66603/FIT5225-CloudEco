# FIT5225-CloudEco
An Environmental Machine Learning-Based Cloud Application in Container Orchestration

### FastAPI (localhost)
```
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

### Docker build container
```
docker build --platform linux/amd64 -t cloudeco:latest .
<!-- docker buildx build --platform linux/amd64 -t alan66603/cloudeco:latest --push . -->
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
python3 -m locust -f locustfile.py --host=<Master external IP>:<NodePort>
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
| 1 | 0.68 | 20 | 11,535 ms | ~30 users | baseline |
| 2 | 1.36 | 40 | 15,309 ms | ~60 users | 2.00× |
| 4 | 2.61 | 70 | 21,242 ms | ~90 users | 3.84× |
| 8 | 4.50 | 100 | 15,770 ms | ~130 users | 6.62× |

#### Analysis

**Methodology**

Load testing was conducted using Locust against the CloudEco wildfire detection API deployed on a 3-node Kubernetes cluster (1 master, 2 workers; e2-custom-4-8192 on GCP). Each worker node provides 4 vCPUs and 8 GB RAM. Pods were constrained to 1.0 vCPU and 2 Gi memory each. The Locust workload mixed `/api/predict` (weight 2) and `/api/annotate` (weight 1) tasks, each carrying a base64-encoded test image, with inter-request wait times of 0.5–1.5 s per user. A 30-second client-side timeout was applied so that requests queued beyond the practical usability threshold are recorded as failures. For each pod count (1, 2, 4, 8), concurrent users were ramped from 5 until the breaking point — defined as the onset of HTTP failures or exponential latency growth — was reached.

**Results and Little's Law Verification**

Little's Law states L = λW, where L is the mean number of requests concurrently in the system, λ is the throughput (arrival rate), and W is the mean sojourn time (response time).

At the saturation point for 1 pod (λ = 0.68 req/s, W = 11.535 s):

> L = 0.68 × 11.535 ≈ **7.8 concurrent requests in the system**

This confirms the server is nearly fully utilised: with only 20 concurrent users driving 0.68 req/s, the system already has ~7.8 requests queued or in service at any moment.

**Queuing Theory Analysis**

Each pod acts as an independent server with a mean service time of approximately 1/μ ≈ 6.4 s (≈ 0.156 req/s per pod). Server utilisation at saturation is ρ = λ / (c × μ), where c is the number of pods. For 1 pod: ρ = 0.68 / (1 × 0.156) ≈ **0.98** (near-full utilisation), confirming the system is CPU-bound.

As pod count doubles, the aggregate service rate c × μ doubles, allowing twice the arrival rate before ρ approaches 1 again. This explains the near-linear throughput scaling (×2.00, ×3.84, ×6.62 for 2, 4, 8 pods respectively). The slight sub-linearity at 8 pods (6.62× instead of 8×) reflects scheduling overhead and CPU contention within shared worker nodes, where multiple pods on the same physical machine compete for CPU time slices.

**Saturation Point and Breaking Point**

The saturation point — where RPS plateaus despite additional users — occurs at approximately 5 concurrent users per pod. Beyond this, the system enters an overloaded regime: the request queue grows unboundedly, response time increases linearly with load, and eventually the 30-second client timeout triggers failures. The breaking point scales roughly linearly with pod count (30 → 60 → 90 → 130 users), demonstrating that horizontal pod scaling provides predictable, proportional capacity expansion.

**Conclusion**

The results confirm that the CloudEco inference service scales near-linearly with pod count under CPU-bound YOLOv8m inference. A single pod sustains 0.68 RPS; eight pods sustain 4.50 RPS (6.62× gain), achieving 83% parallel efficiency. Little's Law and M/M/c queuing theory accurately predict observed throughput and latency behaviour, validating the architectural decision to use stateless, horizontally-scalable pods for ML inference workloads.

#### 1 pod
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users |	20 users（last point with no failure）|
| Avg response time at threshold | 11534.88ms
| Breaking point | 30 users（failure start appearing）
| Max throughput | ~0.68 RPS

Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                            91   10(10.99%) |  12286    1159   30357   6700 |    0.23        0.03
POST     /api/predict                                                            176   18(10.23%) |  11146     958   30622   6100 |    0.45        0.05
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              267   28(10.49%) |  11534     958   30622   6400 |    0.68        0.07

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99%  99.9% 99.99%   100% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                               6700  15000  26000  27000  30000  30000  30000  30000  30000  30000  30000     91
POST     /api/predict                                                                6100  13000  18000  25000  30000  30000  30000  31000  31000  31000  31000    176
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
         Aggregated                                                                  6400  14000  22000  26000  30000  30000  30000  30000  31000  31000  31000    267

Error report
# occurrences      Error                                                                                               
------------------|------------------------------------------------------------------------------------------------------------------------------------
10                 POST /api/annotate: HTTP 0:                                                                         
18                 POST /api/predict: HTTP 0:                                                                          
------------------|------------------------------------------------------------------------------------------------------------------------------------

#### 2 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~40 users（last point with no failure）|
| Avg response time at threshold | ~13,000ms |
| Breaking point | ~60 users（failure start appearing）|
| Max throughput | ~1.36 RPS |

Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                            89   13(14.61%) |  13986    1294   30272  13000 |    0.42        0.06
POST     /api/predict                                                            202   27(13.37%) |  15892    1188   30252  14000 |    0.94        0.13
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              291   40(13.75%) |  15309    1188   30272  13000 |    1.36        0.19

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99%  99.9% 99.99%   100% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              13000  17000  21000  24000  30000  30000  30000  30000  30000  30000  30000     89
POST     /api/predict                                                              14000  20000  24000  25000  30000  30000  30000  30000  30000  30000  30000    202
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
         Aggregated                                                              13000  20000  23000  24000  30000  30000  30000  30000  30000  30000  30000    291

#### 4 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~70 users（last point with no failure）|
| Avg response time at threshold | ~21,000ms |
| Breaking point | ~90 users（failure start appearing）|
| Max throughput | ~2.61 RPS |

Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                           258   10( 3.88%) |  21416    1388   30689  23000 |    0.88        0.03
POST     /api/predict                                                            504   26( 5.16%) |  21154    1164   30139  23000 |    1.73        0.09
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                              762   36( 4.72%) |  21242    1164   30689  23000 |    2.61        0.12

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99%  99.9% 99.99%   100% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              24000  25000  27000  28000  29000  30000  30000  30000  31000  31000  31000    258
POST     /api/predict                                                              23000  25000  26000  27000  29000  30000  30000  30000  30000  30000  30000    504
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
         Aggregated                                                              23000  25000  26000  27000  29000  30000  30000  30000  31000  31000  31000    762

#### 8 pods
| Criterion | Value |
| :--- | :--- |
| Max stable concurrent users | ~100 users（last point with no failure）|
| Avg response time at threshold | ~15,770ms |
| Breaking point | ~130 users（failure start appearing）|
| Max throughput | ~4.50 RPS |

Type     Name                                                                 # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
POST     /api/annotate                                                           682   15( 2.20%) |  16053     145   40654  15000 |    1.43        0.03
POST     /api/predict                                                           1469   54( 3.68%) |  15639     627   36078  14000 |    3.07        0.11
--------|-------------------------------------------------------------------|-------|-------------|-------|-------|-------|-------|--------|-----------
         Aggregated                                                             2151   69( 3.21%) |  15770     145   40654  14000 |    4.50        0.14

Response time percentiles (approximated)
Type     Name                                                                         50%    66%    75%    80%    90%    95%    98%    99%  99.9% 99.99%   100% # reqs
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
POST     /api/annotate                                                              15000  20000  22000  24000  27000  30000  31000  33000  41000  41000  41000    682
POST     /api/predict                                                              14000  19000  22000  24000  26000  28000  30000  30000  35000  36000  36000   1469
--------|-----------------------------------------------------------------------|--------|------|------|------|------|------|------|------|------|------|------|------
         Aggregated                                                              14000  20000  22000  24000  26000  29000  30000  31000  36000  41000  41000   2151

"ONNX Runtime was evaluated but exhibited higher and less stable latency on the e2 VM (avg 1.85s, spikes to 4s) compared to native PyTorch inference (avg 2.21s, stable). This is attributed to ONNX Runtime's internal thread pool contending with the ThreadPoolExecutor under a single vCPU constraint. PyTorch was retained as the inference backend."