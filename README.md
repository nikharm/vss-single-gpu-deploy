# VSS Blueprint: Single GPU Deployment

Deploy [NVIDIA Video Search and Summarization](https://build.nvidia.com/nvidia/video-search-and-summarization/blueprintcard) on a **single H100 GPU**.

All models run locally on one GPU using low-memory modes and GPU sharing:

- **VLM:** Cosmos-Reason2-8B (built-in to VSS engine)
- **LLM:** Llama 3.1 8B Instruct (NIM, low memory mode)
- **Embedding:** llama-3.2-nv-embedqa-1b-v2 (NIM)
- **Reranker:** llama-3.2-nv-rerankqa-1b-v2 (NIM)

| Option | Platform |
|--------|----------|
| [VM](vm/) | Docker Compose on standalone VM |
| [AKS](aks/) | Azure Kubernetes Service with Helm |

## Prerequisites

- **NGC API Key:** https://ngc.nvidia.com
- **Hugging Face Token:** Accept [Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B) terms
- **Azure subscription** with H100 quota (Standard_NC40ads_H100_v5)

## Official Docs

- [VSS Blueprint Overview](https://build.nvidia.com/nvidia/video-search-and-summarization/blueprintcard)
- [VSS GitHub Repository](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization)
- [VSS Helm Deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html)
- [VSS Docker Compose Single GPU](https://docs.nvidia.com/vss/latest/content/vss_dep_docker_compose_x86.html#fully-local-deployment-single-gpu)
