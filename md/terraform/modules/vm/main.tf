###############################################################################
# terraform/modules/vm/main.tf
#
# 재사용 가능한 VM 생성 모듈.
# - cloud-init 템플릿(VMID 9000)을 clone해서 VM 1대 생성
# - cloud-init으로 IP, SSH 키, hostname 자동 주입
# - 호출하는 곳마다 다른 이름/IP/사양으로 인스턴스화
###############################################################################

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.pve_node
  vm_id     = var.vmid
  tags      = var.tags

  # Proxmox 호스트 부팅 시 자동 시작
  # - 운영 환경에서 중요 (전원 복구 후 자동 복귀)
  on_boot = true

  ###########################################################################
  # 템플릿에서 clone
  # - full = true : 독립 디스크 (linked clone 대신, 안정성 우선)
  # - linked clone은 빠르지만 템플릿 변경에 영향받음
  ###########################################################################
  clone {
    vm_id     = var.template_vm_id
    node_name = var.template_vm_node
    full      = true
  }

  ###########################################################################
  # CPU
  # - type = "host" : 호스트 CPU 그대로 노출
  #   → nested virtualization 가능 (Proxmox 위 K8s 위 컨테이너)
  #   → AVX 등 모든 CPU instruction 사용 가능
  ###########################################################################
  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory # MB 단위
  }

  ###########################################################################
  # QEMU Guest Agent
  # - cloud-init image에 포함되어 있음
  # - VM의 IP 등 정보를 Proxmox API로 조회 가능
  # - 종료 시 정상 shutdown 명령 전달
  ###########################################################################
  agent {
    enabled = true
  }

  ###########################################################################
  # 디스크
  # - 템플릿 디스크에서 resize
  # - discard = "on" : SSD trim 지원 (LVM-thin storage)
  # - ssd = true : guest OS에 SSD로 노출 (성능 ↑)
  ###########################################################################
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  ###########################################################################
  # 네트워크
  # - VLAN-aware 브리지 vmbr0에 연결
  # - vlan_id : Proxmox 측에서 VLAN 태그 부여 (Access 포트처럼 동작)
  # - firewall = false : Proxmox 자체 방화벽 비활성화 (pfSense + K8s NetworkPolicy로 충분)
  #   → fwbr/fwln/fwpr 같은 추가 브리지 안 생김 (CARP 등 충돌 방지)
  ###########################################################################
  network_device {
    bridge   = var.bridge
    vlan_id  = var.vlan_tag
    model    = "virtio" # 가장 성능 좋음
    firewall = false
  }

  ###########################################################################
  # cloud-init 설정
  # - 부팅 시 한 번 실행되어 IP/SSH키/사용자 자동 설정
  # - 이 덕분에 VM 만들면 1분 안에 SSH 접속 가능
  ###########################################################################
  initialization {
    datastore_id = var.datastore_id

    # IPv4 정적 IP (CIDR 형식, 예: "172.16.23.10/24")
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    # DNS
    dns {
      servers = var.dns_servers
    }

    # ubuntu 사용자에 SSH 공개키 등록
    # → ssh ubuntu@<IP> 로 비밀번호 없이 접속 가능
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
      # password 설정 안 함 → SSH 키만으로 인증
    }
  }

  # serial console (cloud-init 출력 확인용, 디버깅에 유용)
  serial_device {}

  operating_system {
    type = "l26" # Linux 2.6+ kernel
  }

  ###########################################################################
  # 변경 무시 — 템플릿 이미지가 업데이트되어도 기존 VM 재생성 안 함
  ###########################################################################
  lifecycle {
    ignore_changes = [
      clone, # clone 블록 변경 시 무시
    ]
  }
}
