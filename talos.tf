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
