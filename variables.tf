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

variable "prefix" {
  default = "terraform-talos-example"
}
