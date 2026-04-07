# FIT5225-CloudEco
An Environmental Machine Learning-Based Cloud Application in Container Orchestration


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