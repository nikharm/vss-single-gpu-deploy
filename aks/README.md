# VSS on AKS (Helm)

## Prerequisites

- Azure CLI, kubectl, helm
- Azure subscription with H100 quota (Standard_NC40ads_H100_v5)
- NGC API Key + Hugging Face Token

## Deploy

### 1. Create AKS cluster

```bash
az account set --subscription "<your-subscription>"

az group create --name rg-vss-aks --location westeurope

az aks create \
  --resource-group rg-vss-aks \
  --name aks-vss \
  --location westeurope \
  --node-count 1 \
  --node-vm-size Standard_D8s_v5 \
  --generate-ssh-keys \
  --network-plugin azure \
  --enable-managed-identity

az aks nodepool add \
  --resource-group rg-vss-aks \
  --cluster-name aks-vss \
  --name gpupool \
  --node-count 1 \
  --node-vm-size Standard_NC40ads_H100_v5 \
  --labels hardware=gpu \
  --node-osdisk-size 512

az aks get-credentials --resource-group rg-vss-aks --name aks-vss --overwrite-existing
```

### 2. Install GPU Operator

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true

# Verify (~1-2 min)
kubectl get nodes -o json | jq '.items[].status.allocatable["nvidia.com/gpu"]'
```

### 3. Create secrets

```bash
export NGC_API_KEY="<your-key>"
export HF_TOKEN="<your-token>"

kubectl create secret docker-registry ngc-docker-reg-secret \
  --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_API_KEY

kubectl create secret generic graph-db-creds-secret \
  --from-literal=username=neo4j --from-literal=password=password

kubectl create secret generic arango-db-creds-secret \
  --from-literal=username=root --from-literal=password=password

kubectl create secret generic minio-creds-secret \
  --from-literal=access-key=minio --from-literal=secret-key=minio123

kubectl create secret generic ngc-api-key-secret --from-literal=NGC_API_KEY=$NGC_API_KEY
kubectl create secret generic hf-token-secret --from-literal=HF_TOKEN=$HF_TOKEN
```

### 4. Deploy VSS

```bash
helm install vss-blueprint nvidia-blueprint-vss-2.4.1.tgz -f overrides-single-gpu.yaml

watch -n 5 kubectl get pods  # wait for all 1/1 Running (~15-30 min)
```

### 5. Access

```bash
kubectl port-forward svc/vss-service 8100:8000 &
curl http://localhost:8100/health/ready
```

- **UI:** http://localhost:9100 (also port-forward: `kubectl port-forward svc/vss-service 9100:9100 &`)
- **API:** http://localhost:8100

## Usage

### Local download (default)

```bash
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

Downloads the video to your machine, uploads through port-forward, and saves results to `summaries/`.

### On-cluster download (faster for large videos)

```bash
./summarize_url_cluster.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
```

Downloads and uploads the video entirely on the AKS cluster via `kubectl exec`, so video bytes never leave the cluster network. Only the small JSON summarize request/response travels through the local port-forward. Results are saved to `summaries-cluster/`.

### Customizing prompts

The `/summarize` API accepts three prompts (see `summarize_url.sh`):

- `prompt` -- per-chunk VLM caption prompt (what Cosmos-Reason2 describes per video chunk)
- `caption_summarization_prompt` -- how chunk captions are structured
- `summary_aggregation_prompt` -- how the final summary is aggregated

Edit these in `summarize_url.sh` or pass them directly via the API.

## Cost control

```bash
# Scale GPU to 0 (stop billing)
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 0

# Scale back up
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 1

# Delete all
az group delete -n rg-vss-aks --yes
```

## Scaling

This setup shares a single GPU across all services (demo/dev). To scale for production:

1. **Add GPU nodes**: `az aks nodepool scale ... --node-count 4`
2. **Update overrides** - remove single-GPU sharing config:
   ```yaml
   vss:
     replicas: 3  # parallel video processors
     resources:
       limits:
         nvidia.com/gpu: 1  # dedicated GPU per replica
   ```
3. **Remove** `NVIDIA_VISIBLE_DEVICES=0` and `nvidia.com/gpu: 0` from all components
4. Each VSS replica gets its own GPU for concurrent video processing

See [NVIDIA VSS docs](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html) for production configurations.

## Notes

- All services share GPU 0 via `NVIDIA_VISIBLE_DEVICES=0` with `nvidia.com/gpu: 0`
- Don't add taints to GPU node pool
- `overrides-single-gpu.yaml` includes fsGroup fix for rerank PVC permissions
- **Names must match**: The overrides file references `agentpool: gpupool` and `ngc-docker-reg-secret`. If you use different names when creating the nodepool or secrets, update the overrides accordingly.
