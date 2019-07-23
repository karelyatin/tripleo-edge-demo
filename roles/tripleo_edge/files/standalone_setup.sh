#!/usr/bin/env bash

set -eu

PATH=$PATH:/usr/sbin:/sbin

openstack tripleo container image prepare default \
  --output-env-file $HOME/containers-prepare-parameters.yaml

sudo yum install -y iproute
#Adjust if u have other interface settings
export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETMASK=24
# We need the gateway as we'll be reconfiguring the eth0 interface
export GATEWAY=`ip r get 1.1.1.1 | awk '/dev/{print $3}' | tr -d '[[:space:]]'`
export INTERFACE=`ip r get 1.1.1.1 | awk '/dev/{print $5}' | tr -d '[[:space:]]'`
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`
if [ -z $DOMAIN ]; then export DOMAIN=localdomain;fi

cat <<EOF > $HOME/standalone_parameters.yaml
parameter_defaults:
  #selinux permissive needed at least for pacemaker scenarios
  SELinuxMode: permissive
  ContainerCli: podman
  CloudDomain: $DOMAIN
  CloudName: $IP
  # default gateway
  ControlPlaneStaticRoutes:
    - ip_netmask: 0.0.0.0/0
      next_hop: $GATEWAY
      default: true
  Debug: true
  DeploymentUser: $USER
  DnsServers:
    - 1.1.1.1
    - 8.8.8.8
  # needed for vip & pacemaker
  KernelIpNonLocalBind: 1
  DockerInsecureRegistryAddress:
    - $IP:8787
  NeutronPublicInterface: $INTERFACE
  # domain name used by the host
  NeutronDnsDomain: localdomain
  # re-use ctlplane bridge for public net, defined in the standalone
  # net config (do not change unless you know what you're doing)
  NeutronBridgeMappings: datacentre:br-ctlplane
  NeutronPhysicalBridge: br-ctlplane
  # enable to force metadata for public net
  #NeutronEnableForceMetadata: true
  StandaloneEnableRoutedNetworks: false
  StandaloneHomeDir: $HOME
  InterfaceLocalMtu: 1450
  # Needed if running in a VM, not needed if on baremetal
  NovaComputeLibvirtType: qemu
  StandaloneExtraConfig:
     oslo_messaging_notify_use_ssl: false
     oslo_messaging_rpc_use_ssl: false
EOF

