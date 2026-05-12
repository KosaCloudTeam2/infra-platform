###############################################################################
# terraform/onprem/providers.tf
#
# Proxmox API를 사용해 VM을 생성/관리하기 위한 Provider 설정.
# - 사용 provider: bpg/proxmox (현재 가장 활발한 메인테인. Telmate/proxmox는 구버전)
# - state: 초기엔 로컬 파일 (terraform.tfstate). 안정 후 Ceph RGW(S3) 이전 권장.
###############################################################################

terraform {
  # Terraform 최소 버전. 1.5+ 권장 (configurable validate, check 블록 등 기능)
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66" # 0.66.x 안정. 새 버전 나오면 changelog 확인 후 업데이트
    }
  }

  # 로컬 state로 시작. 나중에 다음 backend로 이전:
  #
  # backend "s3" {
  #   bucket                      = "kosa-terraform-state"
  #   key                         = "onprem/terraform.tfstate"
  #   endpoint                    = "https://s3.kosa.local"   # Ceph RGW
  #   region                      = "us-east-1"               # MinIO/RGW는 임의 값 OK
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   force_path_style            = true
  # }
}

###############################################################################
# Proxmox API 접속 정보
#
# - endpoint   : Proxmox Web UI URL (포트 8006)
# - api_token  : root@pam!<token-id>=<secret> 형식
#                Proxmox UI > Datacenter > Permissions > API Tokens 에서 발급
# - insecure   : 자체서명 인증서 허용 (사내망이라 true. 공인 인증서면 false)
# - ssh        : bpg provider가 일부 작업(예: disk import)에서 SSH 접근 필요
###############################################################################

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.proxmox_ssh_private_key_path)
  }
}
