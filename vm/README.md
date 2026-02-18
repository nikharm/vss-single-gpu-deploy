# VSS on VM: Single H100 GPU (Docker Compose)

Deploy the NVIDIA Video Search and Summarization blueprint on a standalone VM using Docker Compose.

This follows the [official NVIDIA recipe](https://docs.nvidia.com/vss/latest/content/vss_dep_docker_compose_x86.html#fully-local-deployment-single-gpu) exactly.

---

## Prerequisites

### VM requirements

- **OS:** Ubuntu 22.04
- **GPU:** 1× H100 (80GB+), or 1× RTX PRO 6000 Blackwell SE
- **Disk:** **200GB+ free** (100GB for Docker images, 50GB for model cache, 50GB buffer)
- **NVIDIA:** Driver 580.65.06+, CUDA 13.0+
- **Docker:** 27.5.1+ with NVIDIA Container Toolkit 1.13.5+
- **Docker Compose:** 2.32.4+

### Azure VM (recommended)

```bash
# Create resource group
az group create --name rg-vss-vm --location westeurope

# Create VM with H100
az vm create \
  --resource-group rg-vss-vm \
  --name vss-vm \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_NC40ads_H100_v5 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --os-disk-size-gb 256 \
  --public-ip-sku Standard

# Get public IP
az vm show -g rg-vss-vm -n vss-vm -d --query publicIps -o tsv
```

### VM setup (run on VM)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

---

## Step 1: Clone NVIDIA repo

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git
cd video-search-and-summarization/deploy/docker
```

---

## Step 2: Login to NGC

```bash
docker login nvcr.io
# Username: $oauthtoken
# Password: <your NGC API key from https://build.nvidia.com>
```

---

## Step 3: Start NIMs

Copy `run_nims_single_gpu.sh` from this repo to the VM, or run manually:

```bash
export NGC_API_KEY="<your-ngc-api-key>"
export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "$LOCAL_NIM_CACHE"

# LLM (port 8007)
docker run -d -u $(id -u) \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8007:8000 \
  -e NIM_LOW_MEMORY_MODE=1 \
  -e NIM_RELAX_MEM_CONSTRAINTS=1 \
  --name vss-llm-8b \
  nvcr.io/nim/meta/llama-3.1-8b-instruct:1.12.0

# Embedding (port 8006)
docker run -d -u $(id -u) \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8006:8000 \
  -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
  -e NIM_TRT_ENGINE_HOST_CODE_ALLOWED=1 \
  --name vss-embed \
  nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0

# Reranker (port 8005)
docker run -d -u $(id -u) \
  --gpus '"device=0"' --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -p 8005:8000 \
  -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
  --name vss-rerank \
  nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0
```

Wait for all three NIMs to be healthy:

```bash
curl http://localhost:8007/v1/health/ready  # LLM
curl http://localhost:8006/v1/health/ready  # Embedding
curl http://localhost:8005/v1/health/ready  # Reranker
```

---

## Step 4: Configure and start VSS

```bash
cd local_deployment_single_gpu

# Edit .env file
# Set: NGC_API_KEY=<your-key>
# Set: HF_TOKEN=<your-huggingface-token>

docker compose up
```

Wait for: `Docker Compose deployment finished`

---

## Step 5: Test

- **UI:** http://<vm-ip>:9100
- **API:** http://<vm-ip>:8100

```bash
# Health check
curl http://localhost:8100/health/ready

# Check models
curl http://localhost:8100/models
# → Cosmos-Reason2-8B

# Test summarization
curl -X POST http://localhost:8100/summarize \
  -H "Content-Type: application/json" \
  -d '{"video_url": "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"}'
```

---

## Stopping

```bash
# Stop VSS
cd local_deployment_single_gpu
docker compose down

# Stop NIMs
docker stop vss-llm-8b vss-embed vss-rerank
```

---

## Cost control (Azure)

```bash
# Deallocate VM (stops billing for compute, keeps disk)
az vm deallocate --resource-group rg-vss-vm --name vss-vm

# Start VM
az vm start --resource-group rg-vss-vm --name vss-vm

# Delete everything
az group delete --name rg-vss-vm --yes
```

---

## Common issues

### Disk space errors

The single-GPU deployment needs ~150GB total. If you see "no space left on device":

```bash
# Check disk usage
df -h

# Clean Docker
docker system prune -af
```

Consider using a larger OS disk (256GB+) or attaching a data disk.

### NIM not starting

Check logs:
```bash
docker logs vss-llm-8b
docker logs vss-embed
docker logs vss-rerank
```

Common causes:
- Missing `NGC_API_KEY`
- Disk full
- GPU not accessible (check `nvidia-smi`)

---

## Files

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `run_nims_single_gpu.sh` | Script to start all three NIMs |

**Note:** `compose.yaml`, `config.yaml`, and `.env` come from the [NVIDIA repo](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization/tree/main/deploy/docker/local_deployment_single_gpu).
