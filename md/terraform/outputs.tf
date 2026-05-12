###############################################################################
# outputs.tf
# - VM 정보 출력
# - Ansible inventory를 YAML 형식으로 생성 (scripts/generate-inventory.sh에서 사용)
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

###############################################################################
# Ansible inventory (YAML)
#
# 사용:
#   terraform output -raw ansible_inventory > ../ansible/inventory/hosts.yml
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
        bastion = {
          hosts = {
            "${module.bastion.name}" = {
              ansible_host = module.bastion.ipv4
            }
          }
        }
        k8s_control_plane = {
          hosts = {
            for k, v in module.k8s_control_plane : v.name => {
              ansible_host = v.ipv4
            }
          }
        }
        k8s_workers = {
          hosts = {
            for k, v in module.k8s_worker : v.name => {
              ansible_host = v.ipv4
            }
          }
        }
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
