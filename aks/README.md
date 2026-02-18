# VSS on AKS: Single H100 GPU

Deploy the NVIDIA Video Search and Summarization blueprint on Azure Kubernetes Service with a single H100 GPU.

## What gets deployed

| Component | Image/Model | GPU |
|-----------|-------------|-----|
| LLM | llama-3.1-8b-instruct (NIM) | Shared GPU 0 |
| VLM | Cosmos-Reason2-8B (built-in) | Shared GPU 0 |
| Embedding | llama-3.2-nv-embedqa-1b-v2 (NIM) | Shared GPU 0 |
| Reranker | llama-3.2-nv-rerankqa-1b-v2 (NIM) | Shared GPU 0 |
| Databases | Neo4j, Milvus, Elasticsearch, ArangoDB, MinIO | None |

All services share a single GPU via `NVIDIA_VISIBLE_DEVICES=0` with `nvidia.com/gpu: 0` (bypasses Kubernetes device plugin).

---

## Prerequisites

- Azure CLI installed and logged in
- `kubectl` and `helm` installed
- Azure subscription with H100 quota (Standard_NC40ads_H100_v5)
- NGC API Key and Hugging Face token

---

## Step 1: Create AKS cluster

```bash
# Set your subscription
az account set --subscription "<your-subscription-name-or-id>"

# Create resource group
az group create --name rg-vss-single-gpu --location westeurope

# Create AKS cluster with system node pool
az aks create \
  --resource-group rg-vss-single-gpu \
  --name aks-vss \
  --location westeurope \
  --node-count 1 \
  --node-vm-size Standard_D8s_v5 \
  --generate-ssh-keys \
  --network-plugin azure \
  --enable-managed-identity

# Add GPU node pool (NO taint - important!)
az aks nodepool add \
  --resource-group rg-vss-single-gpu \
  --cluster-name aks-vss \
  --name gpupool \
  --node-count 1 \
  --node-vm-size Standard_NC40ads_H100_v5 \
  --labels hardware=gpu \
  --node-osdisk-size 512

# Get credentials
az aks get-credentials --resource-group rg-vss-single-gpu --name aks-vss --overwrite-existing
```

---

## Step 2: Install GPU Operator

AKS pre-installs NVIDIA driver and toolkit, but NOT the device plugin. Install GPU Operator with driver/toolkit disabled:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=false \
  --set operator.runtimeClass=nvidia-container-runtime

# Verify GPU is visible (~1-2 min)
kubectl get nodes -o json | jq '.items[].status.allocatable["nvidia.com/gpu"]'
# Should show "1" for the GPU node
```

---

## Step 3: Create secrets

```bash
export NGC_API_KEY="<your-ngc-api-key>"
export HF_TOKEN="<your-huggingface-token>"

kubectl create secret docker-registry ngc-docker-reg-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY

kubectl create secret generic graph-db-creds-secret \
  --from-literal=username=neo4j --from-literal=password=password

kubectl create secret generic arango-db-creds-secret \
  --from-literal=username=root --from-literal=password=password

kubectl create secret generic minio-creds-secret \
  --from-literal=access-key=minio --from-literal=secret-key=minio123

kubectl create secret generic ngc-api-key-secret \
  --from-literal=NGC_API_KEY=$NGC_API_KEY

kubectl create secret generic hf-token-secret \
  --from-literal=HF_TOKEN=$HF_TOKEN
```

---

## Step 4: Download Helm chart

```bash
# Download the VSS Helm chart from NVIDIA
helm fetch https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-vss-2.4.1.tgz
```

---

## Step 5: Deploy VSS

```bash
helm install vss-blueprint nvidia-blueprint-vss-2.4.1.tgz \
  --set global.ngcImagePullSecretName=ngc-docker-reg-secret \
  -f overrides-single-gpu.yaml

# Monitor pods (~15-30 min first time)
watch -n 5 kubectl get pods
```

Wait until all pods show `1/1 Running`.

---

## Step 6: Test

```bash
# Port forward
kubectl port-forward svc/vss-service 8100:8000 &

# Health check
curl http://localhost:8100/health/ready

# Check models
curl http://localhost:8100/models
# Should return: Cosmos-Reason2-8B

# Test summarization
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

---

## Cost control

```bash
# Scale GPU node pool to 0 (stops GPU billing)
az aks nodepool scale \
  --resource-group rg-vss-single-gpu \
  --cluster-name aks-vss \
  --name gpupool \
  --node-count 0

# Scale back up when needed
az aks nodepool scale \
  --resource-group rg-vss-single-gpu \
  --cluster-name aks-vss \
  --name gpupool \
  --node-count 1

# Delete everything
az group delete --name rg-vss-single-gpu --yes
```

---

## Key findings / issues solved

### 1. GPU resource limits

The Helm chart has two places for GPU limits. Set `nvidia.com/gpu: 0` at BOTH levels:
- Top-level: `nim-llm.resources.limits`
- Nested: `applicationSpecs.*.containers.*.resources.limits`

### 2. No GPU node taint

Don't add taints to the GPU node pool. Pods with `nvidia.com/gpu: 0` won't auto-tolerate GPU taints.

### 3. nemo-rerank PVC permissions

The rerank pod needs `securityContext.fsGroup: 1000` to write to its PVC. This is in the overrides file.

### 4. NVIDIA_VISIBLE_DEVICES works on AKS

Despite NVIDIA docs warning it "might not work on managed K8s", it works on default AKS GPU nodes (they use legacy NVIDIA Container Toolkit, not CDI).

---

## Files

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `overrides-single-gpu.yaml` | Helm values for single-GPU deployment |
| `summarize_url.sh` | Test script to summarize a video URL |
