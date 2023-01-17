# About

An example [Talos Linux Kubernetes cluster](https://www.talos.dev/) in vSphere Virtual Machines using terraform.

# Usage (Ubuntu 22.04 host)

Install Terraform and govc:

```bash
wget https://releases.hashicorp.com/terraform/1.3.7/terraform_1.3.7_linux_amd64.zip
unzip terraform_1.3.7_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
wget https://github.com/vmware/govmomi/releases/download/v0.29.0/govc_Linux_x86_64.tar.gz
tar xf govc_Linux_x86_64.tar.gz govc
sudo install govc /usr/local/bin/govc
rm govc govc_Linux_x86_64.tar.gz
```

Save your environment details as a script that sets the terraform variables from environment variables, e.g.:

```bash
cat >secrets.sh <<'EOF'
export TF_VAR_prefix='terraform-talos-example'
export TF_VAR_vsphere_user='administrator@vsphere.local'
export TF_VAR_vsphere_password='password'
export TF_VAR_vsphere_server='vsphere.local'
export TF_VAR_vsphere_datacenter='Datacenter'
export TF_VAR_vsphere_compute_cluster='Cluster'
export TF_VAR_vsphere_datastore='Datastore'
export TF_VAR_vsphere_network='VM Network'
export TF_VAR_vsphere_folder='terraform-talos-example'
export TF_VAR_vsphere_talos_template='vagrant-templates/talos-1.3.2-amd64'
export GOVC_INSECURE='1'
export GOVC_URL="https://$TF_VAR_vsphere_server/sdk"
export GOVC_USERNAME="$TF_VAR_vsphere_user"
export GOVC_PASSWORD="$TF_VAR_vsphere_password"
EOF
```

**NB** You could also add these variables definitions into a `terraform.tfvars` file, but I find the environment variables more versatile as they can also be used from other tools, like govc.

Install talosctl:

```bash
talos_version='1.3.2'
wget https://github.com/siderolabs/talos/releases/download/v$talos_version/talosctl-linux-amd64
sudo install talosctl-linux-amd64 /usr/local/bin/talosctl
rm talosctl-linux-amd64
```

Install the talos VM template into vSphere:

```bash
source secrets.sh
talos_version='1.3.2'
wget \
  -O talos-$talos_version-vmware-amd64.ova \
  https://github.com/siderolabs/talos/releases/download/v$talos_version/vmware-amd64.ova
govc import.spec talos-$talos_version-vmware-amd64.ova \
  | jq \
      --arg network "$TF_VAR_vsphere_network" \
      '.NetworkMapping[0].Network = $network' \
  >talos-$talos_version-vmware-amd64.ova.json
govc import.ova \
  -ds $TF_VAR_vsphere_datastore \
  -folder "//$TF_VAR_vsphere_datacenter/vm/$(dirname $TF_VAR_vsphere_talos_template)" \
  -name $(basename $TF_VAR_vsphere_talos_template) \
  -options talos-$talos_version-vmware-amd64.ova.json \
  talos-$talos_version-vmware-amd64.ova
vm_ipath="//$TF_VAR_vsphere_datacenter/vm/$TF_VAR_vsphere_talos_template"
govc vm.upgrade -vm.ipath "$vm_ipath"
govc vm.markastemplate -vm.ipath "$vm_ipath"
rm -f disk.raw talos-$talos_version-vmware-amd64.*
```

Ensure your machine can access the control plane ports:

| port    | description                 |
|---------|-----------------------------|
| `50000` | talos `apid`                |
| `6443`  | kubernetes `kube-apiserver` |

Review the `locals` variables block, and ensure the network settings are
modified to work in your environment:

```bash
vim main.tf
```

Initialize terraform:

```bash
./do init
```

Create the infrastructure:

```bash
time ./do plan-apply
```

Show talos information:

```bash
export TALOSCONFIG=$PWD/talosconfig.yml
controllers="$(terraform output -raw controllers)"
workers="$(terraform output -raw workers)"
all="$controllers,$workers"
c0="$(echo $controllers | cut -d , -f 1)"
talosctl -n $all version
talosctl -n $all dashboard
```

Show kubernetes information:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
kubectl cluster-info
kubectl get nodes -o wide
```

Destroy the infrastructure:

```bash
time ./do destroy
```

# Troubleshoot

Talos:

```bash
# see https://www.talos.dev/v1.3/advanced/troubleshooting-control-plane/
talosctl -n $c0 service etcd status
talosctl -n $c0 etcd members
talosctl -n $c0 get members
talosctl -n $c0 health --control-plane-nodes $controllers --worker-nodes $workers
talosctl -n $c0 dashboard
talosctl -n $c0 logs controller-runtime
talosctl -n $c0 logs kubelet
talosctl -n $c0 disks
talosctl -n $c0 mounts | sort
talosctl -n $c0 get resourcedefinitions
talosctl -n $c0 get machineconfigs -o yaml
talosctl -n $c0 get staticpods -o yaml
talosctl -n $c0 get staticpodstatus
talosctl -n $c0 get manifests
talosctl -n $c0 get services
talosctl -n $c0 get extensions
talosctl -n $c0 get addresses
talosctl -n $c0 get nodeaddresses
talosctl -n $c0 list -l -r -t f /etc
talosctl -n $c0 list -l -r -t f /system
talosctl -n $c0 list -l -r -t f /var
talosctl -n $c0 list -l /sys/fs/cgroup
talosctl -n $c0 read /proc/cmdline | tr ' ' '\n'
talosctl -n $c0 read /proc/mounts | sort
talosctl -n $c0 read /etc/resolv.conf
talosctl -n $c0 read /etc/containerd/config.toml
talosctl -n $c0 read /etc/cri/containerd.toml
talosctl -n $c0 read /etc/cri/conf.d/cri.toml
talosctl -n $c0 read /etc/kubernetes/kubelet.yaml
talosctl -n $c0 read /etc/kubernetes/bootstrap-kubeconfig
talosctl -n $c0 ps
talosctl -n $c0 containers -k
```

Kubernetes:

```bash
kubectl get events --all-namespaces --watch
kubectl --namespace kube-system get events --watch
kubectl run busybox -it --rm --restart=Never --image=busybox:1.36 -- nslookup -type=a talos.dev
```
