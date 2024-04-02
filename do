#!/bin/bash
set -euo pipefail

# see https://github.com/siderolabs/talos/releases
# renovate: datasource=github-releases depName=siderolabs/talos
talos_version="1.6.7"

# see https://github.com/siderolabs/talos-vmtoolsd/pkgs/container/talos-vmtoolsd
# renovate: datasource=docker depName=siderolabs/talos-vmtoolsd registryUrl=https://ghcr.io
talos_vmtoolsd_extension_version="0.5.0"

export CHECKPOINT_DISABLE='1'
export TF_LOG='DEBUG' # TRACE, DEBUG, INFO, WARN or ERROR.
export TF_LOG_PATH='terraform.log'

export TALOSCONFIG=$PWD/talosconfig.yml
export KUBECONFIG=$PWD/kubeconfig.yml

function step {
  echo "### $* ###"
}

function build_talos_image {
  # see https://www.talos.dev/v1.6/talos-guides/install/boot-assets/
  # see https://www.talos.dev/v1.6/advanced/metal-network-configuration/
  # see Profile type at https://github.com/siderolabs/talos/blob/v1.6.7/pkg/imager/profile/profile.go#L20-L41
  local talos_version_tag="v$talos_version"
  rm -rf tmp/talos
  mkdir -p tmp/talos
  cat >"tmp/talos/talos-$talos_version.yml" <<EOF
arch: amd64
platform: vmware
secureboot: false
version: $talos_version_tag
customization:
  extraKernelArgs:
    - net.ifnames=0
input:
  kernel:
    path: /usr/install/amd64/vmlinuz
  initramfs:
    path: /usr/install/amd64/initramfs.xz
  baseInstaller:
    imageRef: ghcr.io/siderolabs/installer:$talos_version_tag
  systemExtensions:
    - imageRef: ghcr.io/siderolabs/talos-vmtoolsd:$talos_vmtoolsd_extension_version
output:
  kind: image
  imageOptions:
    diskSize: $((2*1024*1024*1024))
    diskFormat: ova
  outFormat: raw
EOF
  docker run --rm -i \
    -v $PWD/tmp/talos:/secureboot:ro \
    -v $PWD/tmp/talos:/out \
    -v /dev:/dev \
    --privileged \
    "ghcr.io/siderolabs/imager:$talos_version_tag" \
    - < "tmp/talos/talos-$talos_version.yml"
  mv tmp/talos/vmware-amd64.ova tmp/talos/talos-$talos_version-vmware-amd64.ova
}

function init {
  step 'build talos image'
  build_talos_image
  step 'terraform init'
  terraform init -lockfile=readonly
}

function plan {
  step 'terraform plan'
  terraform plan -out=tfplan
}

function apply {
  step 'terraform apply'
  terraform apply tfplan
  terraform output -raw talosconfig >talosconfig.yml
  terraform output -raw kubeconfig >kubeconfig.yml
  health
}

function health {
  step 'talosctl health'
  local controllers="$(terraform output -raw controllers)"
  local workers="$(terraform output -raw workers)"
  local c0="$(echo $controllers | cut -d , -f 1)"
  talosctl -e $c0 -n $c0 \
    health \
    --control-plane-nodes $controllers \
    --worker-nodes $workers
}

function destroy {
  terraform destroy -auto-approve
}

case $1 in
  init)
    init
    ;;
  plan)
    plan
    ;;
  apply)
    apply
    ;;
  plan-apply)
    plan
    apply
    ;;
  health)
    health
    ;;
  destroy)
    destroy
    ;;
  *)
    echo $"Usage: $0 {init|plan|apply|plan-apply|health}"
    exit 1
    ;;
esac
