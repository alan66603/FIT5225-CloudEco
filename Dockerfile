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
        torch torchvision \
        --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

