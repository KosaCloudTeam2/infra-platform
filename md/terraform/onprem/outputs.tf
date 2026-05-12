###############################################################################
# terraform/onprem/outputs.tf
#
# 생성된 VM 정보를 output으로 노출.
# - Ansible inventory를 YAML 형식으로 자동 생성 → scripts/generate-inventory.sh가 사용
###############################################################################

output "control_plane_ips" {
  description = "K8s Control Plane 노드들의 IP 매핑"
  value = {
    for k, v in module.k8s_control_plane : k => v.ipv4
  }
}

output "worker_ips" {
  description = "K8s Worker 노드들의 IP 매핑"
  value = {
    for k, v in module.k8s_worker : k => v.ipv4
  }
}

output "bastion_ip" {
  description = "Bastion VM IP"
  value       = module.bastion.ipv4
}

output "all_vm_summary" {
  description = "전체 VM 요약 (디버깅 용도)"
  value = concat(
    [for k, v in module.k8s_control_plane : "${v.name} (${v.ipv4}) on ${v.pve_node}"],
    [for k, v in module.k8s_worker : "${v.name} (${v.ipv4}) on ${v.pve_node}"],
    ["${module.bastion.name} (${module.bastion.ipv4}) on ${module.bastion.pve_node}"]
  )
}

###############################################################################
# Ansible inventory (YAML 자동 생성)
#
# 사용법:
#   terraform output -raw ansible_inventory > ../../ansible/inventory/hosts.yml
#
# 또는 scripts/generate-inventory.sh 가 자동 처리.
###############################################################################

output "ansible_inventory" {
  description = "Ansible 호환 YAML inventory"
  value = yamlencode({
    all = {
      vars = {
        ansible_user                 = "ubuntu"
        ansible_ssh_private_key_file = "~/.ssh/kosa_iac"
        ansible_python_interpreter   = "/usr/bin/python3"
      }
      children = {
        # 관리망에 있는 Bastion (Ansible 실행 위치)
        bastion = {
          hosts = {
            "${module.bastion.name}" = {
              ansible_host = module.bastion.ipv4
            }
          }
        }

        # K8s Control Plane (3대)
        k8s_control_plane = {
          hosts = {
            for k, v in module.k8s_control_plane : v.name => {
              ansible_host = v.ipv4
            }
          }
        }

        # K8s Workers (3대)
        k8s_workers = {
          hosts = {
            for k, v in module.k8s_worker : v.name => {
              ansible_host = v.ipv4
            }
          }
        }

        # K8s 전체 (CP + Workers) — 두 그룹을 묶어서 한꺼번에 처리 가능
        k8s_cluster = {
          children = {
            k8s_control_plane = {}
            k8s_workers       = {}
          }
        }
      }
    }
  })
}
