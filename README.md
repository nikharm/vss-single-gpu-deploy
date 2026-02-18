# VSS Blueprint: Single GPU Deployment

Deploy [NVIDIA Video Search and Summarization](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization) on a **single H100 GPU**.

| Option | Platform |
|--------|----------|
| [VM](vm/) | Docker Compose on standalone VM |
| [AKS](aks/) | Azure Kubernetes Service with Helm |

## Prerequisites

- **NGC API Key:** https://ngc.nvidia.com
- **Hugging Face Token:** Accept [Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B) terms
- **Azure subscription** with H100 quota (Standard_NC40ads_H100_v5)

## Official Docs

- [VSS Blueprint Overview](https://docs.nvidia.com/vss/latest/content/overview.html)
- [VSS Helm Deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html)
- [VSS Docker Compose Deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_docker.html)
