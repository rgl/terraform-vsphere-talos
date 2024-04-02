# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.7.5"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.6.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/vsphere
    # see https://github.com/hashicorp/terraform-provider-vsphere
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.7.0"
    }
    # see https://registry.terraform.io/providers/siderolabs/talos
    # see https://github.com/siderolabs/terraform-provider-talos
    talos = {
      source  = "siderolabs/talos"
      version = "0.4.0"
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
  default = "templates/talos-1.6.7-amd64"
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

# see https://github.com/siderolabs/talos/releases
# see https://www.talos.dev/v1.6/introduction/support-matrix/
variable "talos_version" {
  type = string
  # renovate: datasource=github-releases depName=siderolabs/talos
  default = "1.6.7"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.talos_version))
    error_message = "Must be a version number."
  }
}

# see https://github.com/siderolabs/kubelet/pkgs/container/kubelet
# see https://www.talos.dev/v1.6/introduction/support-matrix/
variable "kubernetes_version" {
  type = string
  # renovate: datasource=github-releases depName=siderolabs/kubelet
  default = "1.29.3"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.kubernetes_version))
    error_message = "Must be a version number."
  }
}

variable "cluster_name" {
  type    = string
  default = "example"
}

locals {
  netmask          = 24
  net              = "10.17.4"
  gateway          = "${local.net}.1"
  cluster_vip      = "${local.net}.9"
  nameservers      = ["1.1.1.1", "1.0.0.1"]
  timeservers      = ["pool.ntp.org"]
  cluster_endpoint = "https://${local.cluster_vip}:6443" # k8s kube-apiserver endpoint.
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = "${local.net}.${10 + i}"
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = "${local.net}.${20 + i}"
    }
  ]
  common_machine_config = {
    machine = {
      # NB the install section changes are only applied after a talos upgrade
      #    (which we do not do). instead, its preferred to create a custom
      #    talos image, which is created in the installed state.
      #install = {}
      features = {
        # see https://www.talos.dev/v1.6/kubernetes-guides/configuration/kubeprism/
        # see talosctl -n $c0 read /etc/kubernetes/kubeconfig-kubelet | yq .clusters[].cluster.server
        # NB if you use a non-default CNI, you must configure it to use the
        #    https://localhost:7445 kube-apiserver endpoint.
        kubePrism = {
          enabled = true
          port    = 7445
        }
      }
    }
    cluster = {
      # see https://www.talos.dev/v1.6/talos-guides/discovery/
      # see https://www.talos.dev/v1.6/reference/configuration/#clusterdiscoveryconfig
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
    "guestinfo.talos.config" = base64encode(data.talos_machine_configuration.controller[count.index].machine_configuration)
  }
  lifecycle {
    # TODO why is terraform plan trying to modify these?
    ignore_changes = [
      ept_rvi_mode,
      hv_mode,
    ]
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
    "guestinfo.talos.config" = base64encode(data.talos_machine_configuration.worker[count.index].machine_configuration)
  }
  lifecycle {
    # TODO why is terraform plan trying to modify these?
    ignore_changes = [
      ept_rvi_mode,
      hv_mode,
    ]
  }
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/resources/machine_secrets
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}


// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/data-sources/machine_configuration
data "talos_machine_configuration" "controller" {
  count              = var.controller_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "controlplane"
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
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
              # see https://www.talos.dev/v1.6/talos-guides/network/vip/
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
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/data-sources/machine_configuration
data "talos_machine_configuration" "worker" {
  count              = var.worker_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "worker"
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
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
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/data-sources/client_configuration
data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoints            = [for node in local.controller_nodes : node.address]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/data-sources/cluster_kubeconfig
data "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine_bootstrap.talos,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.4.0/docs/resources/machine_bootstrap
resource "talos_machine_bootstrap" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    vsphere_virtual_machine.controller,
  ]
}

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
