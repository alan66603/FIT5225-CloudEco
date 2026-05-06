# AI-generated (Claude, Anthropic): multi-stage build structure, venv isolation, CPU-only
# PyTorch install, and non-root user setup.
# Modified: added libxcb1 (required by OpenCV at runtime); added PYTHONUNBUFFERED and
# PYTHONDONTWRITEBYTECODE env vars; added --log-level warning to CMD.

# ── Stage 1: builder ──────────────────────────────────────────────────────────
# Install all Python dependencies into a virtual environment.
# Keeping this in a separate stage prevents build tools from leaking
# into the final runtime image.
FROM python:3.12-slim AS builder

WORKDIR /build

# Install pip dependencies into an isolated venv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements first to exploit Docker layer caching:
# this layer is only rebuilt when requirements.txt changes.
COPY requirements.txt .

# Install CPU-only PyTorch, then install the remaining application dependencies.
# --no-cache-dir: delete the cache of pip download in container
# torch and torchvision should be installed here instead of by requirements.txt
RUN pip install --no-cache-dir \
        torch==2.5.1 torchvision==0.20.1 \
        --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
# Start from the same slim base; copy only the finished venv and app files.
# This discards all build-time tooling and keeps the final image small.
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install system libraries required by opencv, then clean up apt cache
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxcb1 \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security compliance
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Copy the pre-built virtual environment from the builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source code and model weights
COPY main.py .
COPY wildfire-detection/fire-models/fire_m.pt wildfire-detection/fire-models/fire_m.pt

# Switch to non-root user
USER appuser

# docker run -p xxxx:8000 myimage
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "warning"]