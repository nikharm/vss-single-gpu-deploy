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
  --set toolkit.enabled=false

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
helm install vss-blueprint nvidia-blueprint-vss-2.4.1.tgz \
  --set global.ngcImagePullSecretName=ngc-docker-reg-secret \
  -f overrides-single-gpu.yaml

watch -n 5 kubectl get pods  # wait for all 1/1 Running (~15-30 min)
```

### 5. Test

```bash
kubectl port-forward svc/vss-service 8100:8000 &
curl http://localhost:8100/health/ready
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

## Cost control

```bash
# Scale GPU to 0 (stop billing)
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 0

# Scale back up
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 1

# Delete all
az group delete -n rg-vss-aks --yes
```

## Notes

- All services share GPU 0 via `NVIDIA_VISIBLE_DEVICES=0` with `nvidia.com/gpu: 0`
- Don't add taints to GPU node pool
- `overrides-single-gpu.yaml` includes fsGroup fix for rerank PVC permissions
