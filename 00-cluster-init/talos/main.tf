terraform {
  required_version = "1.6.3"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/siderolabs/talos
    # see https://github.com/siderolabs/terraform-provider-talos
    talos = {
      source  = "siderolabs/talos"
      version = "0.3.4"
    }
  }
}

provider "talos" {
}

variable "controller_count" {
  type    = number
  default = 3
  validation {
    condition     = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type    = number
  default = 2
  validation {
    condition     = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
  default     = "home"
}

locals {
  kubernetes_version                 = "1.28.2" # see https://github.com/siderolabs/kubelet/pkgs/container/kubelet
  talos_version                      = "1.5.2"  # see https://github.com/siderolabs/talos/releases
  talos_version_tag                  = "v${local.talos_version}"
  cluster_endpoint                   = "https://192.168.213.1:6443" # k8s api-server endpoint. (HAproxy IP)
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "home-k8c-pi10${1 + i}"
      address = "192.168.213.${11 + i}"
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "home-k8w-pi10${1 + i}"
      address = "192.168.213.${21 + i}"
    }
  ]
  common_machine_config = {
    machine = {
      install = {
        disk = "/dev/mmcblk0"
        image = "ghcr.io/siderolabs/installer:${local.talos_version}"
        #bootloader = true
        #wipe = false
      },
      network = {
        interfaces = [{
        interface = "enp0s3"
        dhcp      = true
        }]
      }
    }
    cluster = {
      # see https://www.talos.dev/v1.5/talos-guides/discovery/
      # see https://www.talos.dev/v1.5/reference/configuration/#clusterdiscoveryconfig
      discovery = {
        enabled = true
        registries = {
          kubernetes = {
            disabled = false
          }
          service = {
            disabled = true
          }
        }
      }
    }
  }
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/data-sources/machine_configuration
data "talos_machine_configuration" "controller" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "controlplane"
  talos_version      = local.talos_version_tag
  kubernetes_version = local.kubernetes_version
  examples           = false
  docs               = false
  config_patches = [
    yamlencode(local.common_machine_config),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/data-sources/machine_configuration
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "worker"
  talos_version      = local.talos_version_tag
  kubernetes_version = local.kubernetes_version
  examples           = false
  docs               = false
  config_patches = [
    yamlencode(local.common_machine_config),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/data-sources/client_configuration
data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoints            = [for node in local.controller_nodes : node.address]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/data-sources/cluster_kubeconfig
data "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine_bootstrap.talos,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/resources/machine_secrets
resource "talos_machine_secrets" "talos" {
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/resources/machine_configuration_apply
resource "talos_machine_configuration_apply" "controller" {
  count                       = var.controller_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration
  endpoint                    = local.controller_nodes[count.index].address
  node                        = local.controller_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.controller_nodes[count.index].name
        }
      }
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/resources/machine_configuration_apply
resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = local.worker_nodes[count.index].address
  node                        = local.worker_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.worker_nodes[count.index].name
        }
      }
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.3.3/docs/resources/machine_bootstrap
resource "talos_machine_bootstrap" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine_configuration_apply.controller,
  ]
}

#data "talos_machine_disks" "talos" {
#  client_configuration = talos_machine_secrets.talos.client_configuration
#  node                 = local.controller_nodes[0].address
#  filters = {
#    size = "> 200GB"
#    type = "ssd"
#  }
#}

# for example this could be used to pass in list of disks to rook-ceph
#output "ssd_disks" {
#  value = data.talos_machine_disks.talos.disks.*.name
#}

output "talosconfig" {
  value     = data.talos_client_configuration.talos.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = data.talos_cluster_kubeconfig.talos.kubeconfig_raw
  sensitive = true
}

output "controllers" {
  value = join(",", [for node in local.controller_nodes : node.address])
}

output "workers" {
  value = join(",", [for node in local.worker_nodes : node.address])
}
