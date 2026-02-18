# VSS Blueprint: Single GPU Deployment

Deploy NVIDIA's [Video Search and Summarization](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization) blueprint on a **single H100 GPU**.

Two deployment options:

| Option | Platform | Complexity | Best for |
|--------|----------|------------|----------|
| [VM](vm/) | Docker Compose on a standalone VM | Lower | Quick testing, development |
| [AKS](aks/) | Azure Kubernetes Service with Helm | Higher | Production-like, scalable |

Both run the same stack:
- **VLM:** Cosmos-Reason2-8B (built-in)
- **LLM:** Llama 3.1 8B (NIM)
- **Embedding:** llama-3.2-nv-embedqa-1b-v2 (NIM)
- **Reranker:** llama-3.2-nv-rerankqa-1b-v2 (NIM)
- **Databases:** Neo4j, Milvus, ArangoDB, Elasticsearch, MinIO

## Prerequisites

- **NGC API Key:** https://build.nvidia.com (for NIM container access)
- **Hugging Face Token:** Accept [Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B) terms, then create token at https://huggingface.co/settings/tokens
- **Azure subscription** with H100 quota (for either option)

## Quick comparison

| Aspect | VM | AKS |
|--------|----|----|
| Setup time | ~30 min | ~45 min |
| First run (model download) | ~20 min | ~30 min |
| Subsequent runs | ~5 min | ~10 min |
| Cost control | Stop/deallocate VM | Scale node pool to 0 |
| Persistence | Manual | PVCs auto-persist |

## Official docs

- [Docker Compose deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_docker_compose_x86.html#fully-local-deployment-single-gpu)
- [Helm deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html)
