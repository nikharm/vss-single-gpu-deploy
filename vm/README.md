# VSS on VM (Docker Compose)

## Prerequisites

- 1× H100 (80GB+) or RTX PRO 6000 Blackwell SE
- Ubuntu 22.04, Docker 27.5.1+, NVIDIA Container Toolkit 1.13.5+
- 200GB+ disk
- NGC API Key + Hugging Face Token

## Azure VM (optional)

```bash
az group create --name rg-vss-vm --location westeurope

az vm create \
  --resource-group rg-vss-vm \
  --name vss-vm \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_NC40ads_H100_v5 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --os-disk-size-gb 256

ssh azureuser@$(az vm show -g rg-vss-vm -n vss-vm -d --query publicIps -o tsv)
```

### Install Docker + NVIDIA on VM

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## Deploy

```bash
# 1. Copy this vm/ directory to your VM

# 2. Login to NGC
docker login nvcr.io  # user: $oauthtoken, pass: <NGC_API_KEY>

# 3. Start NIMs
export NGC_API_KEY="<your-key>"
./run_nims_single_gpu.sh

# 4. Wait for NIMs to be healthy
curl http://localhost:8007/v1/health/ready  # LLM
curl http://localhost:8006/v1/health/ready  # Embedding
curl http://localhost:8005/v1/health/ready  # Reranker

# 5. Configure and start VSS
cp .env.example .env
# Edit .env: set NGC_API_KEY and HF_TOKEN
source .env
docker compose up
```

**UI:** http://\<vm-ip\>:9100 | **API:** http://\<vm-ip\>:8100

## Stop

```bash
docker compose down
docker stop vss-llm-8b vss-embed vss-rerank
```

## Cost control (Azure)

```bash
az vm deallocate -g rg-vss-vm -n vss-vm  # stop billing
az vm start -g rg-vss-vm -n vss-vm       # resume
az group delete -n rg-vss-vm --yes       # delete all
```
