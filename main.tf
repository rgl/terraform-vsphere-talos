# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.3.9"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/vsphere
    # see https://github.com/hashicorp/terraform-provider-vsphere
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.3.1"
    }
    # see https://registry.terraform.io/providers/siderolabs/talos
    # see https://github.com/siderolabs/terraform-provider-talos
    talos = {
      source  = "siderolabs/talos"
      version = "0.1.1"
    }
  }
}

variable "vsphere_user" {
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  default   = "password"
  sensitive = true
}

variable "vsphere_server" {
  default = "vsphere.local"
}

variable "vsphere_datacenter" {
  default = "Datacenter"
}

variable "vsphere_compute_cluster" {
  default = "Cluster"
}

variable "vsphere_network" {
  default = "VM Network"
}

variable "vsphere_datastore" {
  default = "Datastore"
}

variable "vsphere_folder" {
  default = "example"
}

variable "vsphere_talos_template" {
  default = "templates/talos-1.3.5-amd64"
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "compute_cluster" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "talos_template" {
  name          = var.vsphere_talos_template
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

provider "talos" {
}

variable "prefix" {
  default = "terraform-talos-example"
}

variable "controller_count" {
  type    = number
  default = 1
  validation {
    condition     = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type    = number
  default = 1
  validation {
    condition     = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "cluster_name" {
  type    = string
  default = "example"
}

locals {
  kubernetes_version = "1.26.1"
  netmask            = 24
  gateway            = "10.17.4.1"
  nameservers        = ["1.1.1.1", "1.0.0.1"]
  timeservers        = ["pool.ntp.org"]
  cluster_vip        = "10.17.4.9"
  cluster_endpoint   = "https://${local.cluster_vip}:6443" # k8s kube-apiserver endpoint.
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = "10.17.4.${10 + i}"
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = "10.17.4.${20 + i}"
    }
  ]
  common_machine_config = {
    cluster = {
      # see https://www.talos.dev/v1.3/talos-guides/discovery/
      # see https://www.talos.dev/v1.3/reference/configuration/#clusterdiscoveryconfig
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
      extraManifests = [
        # see https://github.com/mologie/talos-vmtoolsd
        # see https://www.talos.dev/v1.3/talos-guides/install/virtualized-platforms/vmware/
        "https://github.com/mologie/talos-vmtoolsd/releases/download/0.3.1/talos-vmtoolsd-0.3.1.yaml"
      ]
    }
  }
}

resource "vsphere_folder" "folder" {
  path          = var.vsphere_folder
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# see https://www.terraform.io/docs/providers/vsphere/r/virtual_machine.html
resource "vsphere_virtual_machine" "controller" {
  count                       = var.controller_count
  folder                      = vsphere_folder.folder.path
  name                        = "${var.prefix}-${local.controller_nodes[count.index].name}"
  guest_id                    = data.vsphere_virtual_machine.talos_template.guest_id
  firmware                    = data.vsphere_virtual_machine.talos_template.firmware
  num_cpus                    = 4
  num_cores_per_socket        = 4
  memory                      = 2 * 1024
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0
  enable_disk_uuid            = true # NB the VM must have disk.EnableUUID=1 for, e.g., k8s persistent storage.
  resource_pool_id            = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id                = data.vsphere_datastore.datastore.id
  scsi_type                   = data.vsphere_virtual_machine.talos_template.scsi_type
  disk {
    unit_number      = 0
    label            = "os"
    size             = max(data.vsphere_virtual_machine.talos_template.disks.0.size, 40) # [GiB]
    eagerly_scrub    = data.vsphere_virtual_machine.talos_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.talos_template.disks.0.thin_provisioned
  }
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.talos_template.network_interface_types.0
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.talos_template.id
  }
  # NB this extra_config data ends-up inside the VM .vmx file.
  extra_config = {
    "guestinfo.talos.config" = base64encode(talos_machine_configuration_controlplane.controller[count.index].machine_config)
  }
}

# see https://www.terraform.io/docs/providers/vsphere/r/virtual_machine.html
resource "vsphere_virtual_machine" "worker" {
  count                       = var.worker_count
  folder                      = vsphere_folder.folder.path
  name                        = "${var.prefix}-${local.worker_nodes[count.index].name}"
  guest_id                    = data.vsphere_virtual_machine.talos_template.guest_id
  firmware                    = data.vsphere_virtual_machine.talos_template.firmware
  num_cpus                    = 4
  num_cores_per_socket        = 4
  memory                      = 2 * 1024
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0
  enable_disk_uuid            = true # NB the VM must have disk.EnableUUID=1 for, e.g., k8s persistent storage.
  resource_pool_id            = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id                = data.vsphere_datastore.datastore.id
  scsi_type                   = data.vsphere_virtual_machine.talos_template.scsi_type
  disk {
    unit_number      = 0
    label            = "os"
    size             = max(data.vsphere_virtual_machine.talos_template.disks.0.size, 40) # [GiB]
    eagerly_scrub    = data.vsphere_virtual_machine.talos_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.talos_template.disks.0.thin_provisioned
  }
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.talos_template.network_interface_types.0
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.talos_template.id
  }
  # NB this extra_config data ends-up inside the VM .vmx file.
  extra_config = {
    "guestinfo.talos.config" = base64encode(talos_machine_configuration_worker.worker[count.index].machine_config)
  }
}

resource "talos_machine_secrets" "machine_secrets" {
}

resource "talos_machine_configuration_controlplane" "controller" {
  count              = var.controller_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = local.kubernetes_version
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          hostname = local.controller_nodes[count.index].name
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false
              addresses = ["${local.controller_nodes[count.index].address}/${local.netmask}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.gateway
                }
              ]
              vip = {
                ip = local.cluster_vip
              }
            }
          ]
          nameservers = local.nameservers
        }
        time = {
          servers = local.timeservers
        }
      }
    })
  ]
}

resource "talos_machine_configuration_worker" "worker" {
  count              = var.worker_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = local.kubernetes_version
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          hostname = local.worker_nodes[count.index].name
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false
              addresses = ["${local.worker_nodes[count.index].address}/${local.netmask}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.gateway
                }
              ]
            }
          ]
          nameservers = local.nameservers
        }
        time = {
          servers = local.timeservers
        }
      }
    })
  ]
}

resource "talos_client_configuration" "talos" {
  cluster_name    = var.cluster_name
  machine_secrets = talos_machine_secrets.machine_secrets.machine_secrets
  endpoints       = [for n in local.controller_nodes : n.address]
}

resource "talos_machine_bootstrap" "talos" {
  talos_config = talos_client_configuration.talos.talos_config
  endpoint     = local.controller_nodes[0].address
  node         = local.controller_nodes[0].address
}

resource "talos_cluster_kubeconfig" "talos" {
  talos_config = talos_client_configuration.talos.talos_config
  endpoint     = local.controller_nodes[0].address
  node         = local.controller_nodes[0].address
}

output "talosconfig" {
  value     = talos_client_configuration.talos.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.talos.kube_config
  sensitive = true
}

output "controllers" {
  value = join(",", [for node in local.controller_nodes : node.address])
}

output "workers" {
  value = join(",", [for node in local.worker_nodes : node.address])
}
