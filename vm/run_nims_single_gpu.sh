#!/usr/bin/env bash
# Run NIMs for VSS Fully Local Single-GPU deployment.
# Exact recipe from: https://docs.nvidia.com/vss/latest/content/vss_dep_docker_compose_x86.html#fully-local-deployment-single-gpu
# Do not modify image tags, ports, or NIM_* env vars.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "$NGC_API_KEY" ]; then
  echo "Set NGC_API_KEY (from https://build.nvidia.com) and re-run."
  echo "  export NGC_API_KEY=<your-key>"
  exit 1
fi

export LOCAL_NIM_CACHE="${LOCAL_NIM_CACHE:-$HOME/.cache/nim}"
mkdir -p "$LOCAL_NIM_CACHE"

# --- 1. LLM (Llama 3.1 8B) - port 8007 ---
echo "Starting LLM NIM (port 8007)..."
docker run -d -u $(id -u) -it \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8007:8000 \
  -e NIM_LOW_MEMORY_MODE=1 \
  -e NIM_RELAX_MEM_CONSTRAINTS=1 \
  --name vss-llm-8b \
  nvcr.io/nim/meta/llama-3.1-8b-instruct:1.12.0

# --- 2. Embedding NIM - port 8006 ---
echo "Starting Embedding NIM (port 8006)..."
docker run -d -u $(id -u) -it \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8006:8000 -e NIM_SERVER_PORT=8000 \
  -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
  -e NIM_TRT_ENGINE_HOST_CODE_ALLOWED=1 \
  --name vss-embed \
  nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0

# --- 3. Reranker NIM - port 8005 ---
echo "Starting Reranker NIM (port 8005)..."
docker run -d -u $(id -u) -it \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8005:8000 -e NIM_SERVER_PORT=8000 \
  -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
  --name vss-rerank \
  nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0

echo ""
echo "NIMs started. Wait for models to load (first run downloads; check with: docker logs vss-llm-8b)."
echo "Then edit .env (NGC_API_KEY, HF_TOKEN) and run: docker compose up"
echo "UI: http://localhost:9100   API: http://localhost:8100"
