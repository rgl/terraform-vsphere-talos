# About

An example [Talos Linux Kubernetes cluster](https://www.talos.dev/) in vSphere Virtual Machines using terraform.

[Cilium](https://cilium.io) is used to augment the Networking (e.g. the [`LoadBalancer`](https://cilium.io/use-cases/load-balancer/) and [`Ingress`](https://docs.cilium.io/en/stable/network/servicemesh/ingress/) controllers), Observability (e.g. [Service Map](https://cilium.io/use-cases/service-map/)), and Security (e.g. [Network Policy](https://cilium.io/use-cases/network-policy/)).

# Usage (Ubuntu 22.04 host)

Install terraform:

```bash
# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
terraform_version='1.8.1'
wget "https://releases.hashicorp.com/terraform/$terraform_version/terraform_${$terraform_version}_linux_amd64.zip"
unzip "terraform_${$terraform_version}_linux_amd64.zip"
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Install govc:

```bash
wget https://github.com/vmware/govmomi/releases/download/v0.36.2/govc_Linux_x86_64.tar.gz
tar xf govc_Linux_x86_64.tar.gz govc
sudo install govc /usr/local/bin/govc
rm govc govc_Linux_x86_64.tar.gz
```

Install cilium cli:

```bash
# see https://github.com/cilium/cilium-cli/releases
# renovate: datasource=github-releases depName=cilium/cilium-cli
cilium_version='0.16.4'
cilium_url="https://github.com/cilium/cilium-cli/releases/download/v$cilium_version/cilium-linux-amd64.tar.gz"
wget -O- "$cilium_url" | tar xzf - cilium
sudo install cilium /usr/local/bin/cilium
rm cilium
```

Install cilium hubble:

```bash
# see https://github.com/cilium/hubble/releases
# renovate: datasource=github-releases depName=cilium/hubble
hubble_version='0.13.3'
hubble_url="https://github.com/cilium/hubble/releases/download/v$hubble_version/hubble-linux-amd64.tar.gz"
wget -O- "$hubble_url" | tar xzf - hubble
sudo install hubble /usr/local/bin/hubble
rm hubble
```

Save your environment details as a script that sets the terraform variables from environment variables, e.g.:

```bash
cat >secrets.sh <<'EOF'
talos_version='1.6.7'
export TF_VAR_prefix='terraform-talos-example'
export TF_VAR_vsphere_user='administrator@vsphere.local'
export TF_VAR_vsphere_password='password'
export TF_VAR_vsphere_server='vsphere.local'
export TF_VAR_vsphere_datacenter='Datacenter'
export TF_VAR_vsphere_compute_cluster='Cluster'
export TF_VAR_vsphere_datastore='Datastore'
export TF_VAR_vsphere_network='VM Network'
export TF_VAR_vsphere_folder='terraform-talos-example'
export TF_VAR_vsphere_talos_template="vagrant-templates/talos-$talos_version-amd64"
network_prefix='10.17.4'
export TF_VAR_cluster_vip="$network_prefix.9"
export TF_VAR_cluster_endpoint="https://$TF_VAR_cluster_vip:6443"
export TF_VAR_cluster_vip="$network_prefix.9"
export TF_VAR_cluster_node_network="$network_prefix.0/24"
export TF_VAR_cluster_node_network_gateway="$network_prefix.1"
export TF_VAR_cluster_node_network_nameservers="[\"1.1.1.1\", \"1.0.0.1\"]"
export TF_VAR_cluster_node_network_timeservers="[\"pool.ntp.org\"]"
export GOVC_INSECURE='1'
export GOVC_URL="https://$TF_VAR_vsphere_server/sdk"
export GOVC_USERNAME="$TF_VAR_vsphere_user"
export GOVC_PASSWORD="$TF_VAR_vsphere_password"
EOF
```

**NB** Ensure MAC spoofing (MAC address changes) is allowed at the vSwitch of the selected `TF_VAR_vsphere_network` network. This is required by the flannel cni (the default talos cni).

**NB** You could also add these variables definitions into a `terraform.tfvars` file, but I find the environment variables more versatile as they can also be used from other tools, like govc.

Install talosctl:

```bash
source secrets.sh
wget https://github.com/siderolabs/talos/releases/download/v$talos_version/talosctl-linux-amd64
sudo install talosctl-linux-amd64 /usr/local/bin/talosctl
rm talosctl-linux-amd64
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

Create the talos ova image, and initialize terraform:

```bash
./do init
```

Install the talos VM template into vSphere:

```bash
source secrets.sh
govc import.spec tmp/talos/talos-$talos_version-vmware-amd64.ova \
  | jq \
      --arg network "$TF_VAR_vsphere_network" \
      '.NetworkMapping[0].Network = $network' \
  >talos-$talos_version-vmware-amd64.ova.json
govc import.ova \
  -ds $TF_VAR_vsphere_datastore \
  -folder "//$TF_VAR_vsphere_datacenter/vm/$(dirname $TF_VAR_vsphere_talos_template)" \
  -name $(basename $TF_VAR_vsphere_talos_template) \
  -options talos-$talos_version-vmware-amd64.ova.json \
  tmp/talos/talos-$talos_version-vmware-amd64.ova
vm_ipath="//$TF_VAR_vsphere_datacenter/vm/$TF_VAR_vsphere_talos_template"
govc vm.upgrade -vm.ipath "$vm_ipath"
govc vm.change -vm.ipath "$vm_ipath" \
  -g other6xLinux64Guest \
  -e disk.enableUUID=TRUE
govc vm.info -vm.ipath "$vm_ipath" -json >talos-$talos_version-amd64.json
govc vm.markastemplate -vm.ipath "$vm_ipath"
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

Show Cilium information:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
cilium status --wait
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

In another shell, open the Hubble UI:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
cilium hubble ui
```

Execute an example workload:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
kubectl apply -f example.yml
kubectl rollout status deployment/example
kubectl get ingresses,services,pods,deployments
example_ip="$(kubectl get ingress/example -o json | jq -r .status.loadBalancer.ingress[0].ip)"
example_fqdn="$(kubectl get ingress/example -o json | jq -r .spec.rules[0].host)"
example_url="http://$example_fqdn"
curl --resolve "$example_fqdn:80:$example_ip" "$example_url"
echo "$example_ip $example_fqdn" | sudo tee -a /etc/hosts
curl "$example_url"
xdg-open "$example_url"
kubectl delete -f example.yml
```

Destroy the infrastructure:

```bash
time ./do destroy
```

# Troubleshoot

Talos:

```bash
# see https://www.talos.dev/v1.6/advanced/troubleshooting-control-plane/
talosctl -n $all support && rm -rf support && 7z x -osupport support.zip && code support
talosctl -n $c0 service ext-talos-vmtoolsd status
talosctl -n $c0 service etcd status
talosctl -n $c0 etcd status
talosctl -n $c0 etcd alarm list
talosctl -n $c0 etcd members
talosctl -n $c0 get members
talosctl -n $c0 health --control-plane-nodes $controllers --worker-nodes $workers
talosctl -n $c0 inspect dependencies | dot -Tsvg >c0.svg && xdg-open c0.svg
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
talosctl -n $c0 netstat --extend --programs --pods --listening
talosctl -n $c0 list -l -r -t f /etc
talosctl -n $c0 list -l -r -t f /system
talosctl -n $c0 list -l -r -t f /var
talosctl -n $c0 list -l -r /dev
talosctl -n $c0 list -l /sys/fs/cgroup
talosctl -n $c0 read /proc/cmdline | tr ' ' '\n'
talosctl -n $c0 read /proc/mounts | sort
talosctl -n $c0 read /etc/os-release
talosctl -n $c0 read /etc/resolv.conf
talosctl -n $c0 read /etc/containerd/config.toml
talosctl -n $c0 read /etc/cri/containerd.toml
talosctl -n $c0 read /etc/cri/conf.d/cri.toml
talosctl -n $c0 read /etc/kubernetes/kubelet.yaml
talosctl -n $c0 read /etc/kubernetes/kubeconfig-kubelet
talosctl -n $c0 read /etc/kubernetes/bootstrap-kubeconfig
talosctl -n $c0 ps
talosctl -n $c0 containers -k
```

Cilium:

```bash
cilium status --wait
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
cilium config view
cilium hubble ui
# **NB** cilium connectivity test is not working out-of-the-box in the default
# test namespaces and using it in kube-system namespace will leave garbage
# behind.
#cilium connectivity test --test-namespace kube-system
kubectl -n kube-system get leases | grep cilium-l2announce-
```

Kubernetes:

```bash
kubectl get events --all-namespaces --watch
kubectl --namespace kube-system get events --watch
kubectl --namespace kube-system debug node/w0 --stdin --tty --image=busybox:1.36 -- cat /host/etc/resolv.conf
kubectl --namespace kube-system get configmaps coredns --output yaml
pod_name="$(kubectl --namespace kube-system get pods --selector k8s-app=kube-dns --output json | jq -r '.items[0].metadata.name')"
kubectl --namespace kube-system debug $pod_name --stdin --tty --image=busybox:1.36 --target=coredns -- sh -c 'cat /proc/$(pgrep coredns)/root/etc/resolv.conf'
kubectl --namespace kube-system run busybox -it --rm --restart=Never --image=busybox:1.36 -- nslookup -type=a talos.dev
kubectl get crds
kubectl api-resources
```
