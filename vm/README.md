# VSS on VM (Docker Compose)

## Prerequisites

- 1× H100 (80GB+) or RTX PRO 6000 Blackwell SE
- Ubuntu 22.04, Docker 27.5.1+, NVIDIA Container Toolkit 1.13.5+
- 200GB+ disk
- NGC API Key + Hugging Face Token

## Azure VM (optional)

```bash
az account set --subscription "<your-subscription>"

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

## Credentials

Get your keys:
- **NGC_API_KEY**: [NGC](https://ngc.nvidia.com/) → User menu → Setup → Generate API Key
- **HF_TOKEN**: [HuggingFace](https://huggingface.co/settings/tokens) → New token (read access)

## Deploy

```bash
# 1. Copy this vm/ directory to your VM

# 2. Set credentials
export NGC_API_KEY="<your-ngc-key>"
export HF_TOKEN="<your-hf-token>"

# 3. Login to NGC
echo $NGC_API_KEY | docker login nvcr.io -u '$oauthtoken' --password-stdin

# 4. Start NIMs
./run_nims_single_gpu.sh

# 5. Wait for NIMs to be healthy (~3-5 min)
curl http://localhost:8007/v1/health/ready  # LLM
curl http://localhost:8006/v1/health/ready  # Embedding
curl http://localhost:8005/v1/health/ready  # Reranker

# 6. Configure and start VSS
cp .env.example .env
sed -i "s|<your-ngc-api-key>|$NGC_API_KEY|" .env
sed -i "s|<your-huggingface-token>|$HF_TOKEN|" .env
source .env
docker compose up -d

# 7. Wait for VSS to be ready (~5-10 min first run - downloads Cosmos model)
docker logs -f vss-vm-via-server-1  # watch progress
curl http://localhost:8100/health/ready
```

## Usage

**UI:** http://\<vm-ip\>:9100 | **API:** http://\<vm-ip\>:8100

```bash
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

The script uploads the video to VSS, runs summarization, and saves results to `summaries/`.

### Customizing prompts

The `/summarize` API accepts three prompts (see `summarize_url.sh`):

- `prompt` -- per-chunk VLM caption prompt (what Cosmos-Reason2 describes per video chunk)
- `caption_summarization_prompt` -- how chunk captions are structured
- `summary_aggregation_prompt` -- how the final summary is aggregated

Edit these in `summarize_url.sh` or pass them directly via the API.

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
