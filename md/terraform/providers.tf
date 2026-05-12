###############################################################################
# providers.tf
# Proxmox provider 설정 — bpg/proxmox 사용 (Telmate/proxmox는 구버전이라 비추천)
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66" # 0.66 이상 안정 버전. 새 버전 나오면 시험 후 업데이트
    }
  }

  # 초기엔 로컬 state로 시작.
  # 나중에 Ceph RGW나 MinIO 구축 후 S3 backend로 이전 (아래 주석 참고).
  #
  # backend "s3" {
  #   bucket                      = "kosa-terraform-state"
  #   key                         = "k8s/terraform.tfstate"
  #   endpoint                    = "https://s3.kosa.local"
  #   region                      = "us-east-1"   # MinIO/RGW는 임의 값 OK
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   force_path_style            = true
  # }
}

###############################################################################
# Proxmox API 접속 정보
# - endpoint : Proxmox Web UI URL (포트 8006)
# - api_token: root@pam!<token-id>=<secret> 형식
#   → Proxmox UI > Datacenter > Permissions > API Tokens 에서 발급
# - insecure : 자체서명 인증서 허용 (사내망이라 true. 공인 인증서면 false)
###############################################################################

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  # SSH로 일부 작업(예: disk import) 수행 — bpg provider 특성상 필요할 때 있음
  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.proxmox_ssh_private_key_path)
  }
}
