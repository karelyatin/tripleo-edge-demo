#!/usr/bin/env bash

set -eu

PATH=$PATH:/usr/sbin:/sbin

cat > $HOME/standalone_edge.yaml <<EOF
resource_registry:
  OS::TripleO::Services::CACerts: OS::Heat::None
  OS::TripleO::Services::CinderApi: OS::Heat::None
  OS::TripleO::Services::CinderScheduler: OS::Heat::None
  OS::TripleO::Services::Clustercheck: OS::Heat::None
  OS::TripleO::Services::HAproxy: OS::Heat::None
  OS::TripleO::Services::Horizon: OS::Heat::None
  OS::TripleO::Services::Keystone: OS::Heat::None
  OS::TripleO::Services::Memcached: OS::Heat::None
  OS::TripleO::Services::PlacementApi: OS::Heat::None
  OS::TripleO::Services::MySQL: OS::Heat::None
  OS::TripleO::Services::NeutronApi: OS::Heat::None
  OS::TripleO::Services::NeutronDhcpAgent: OS::Heat::None
  OS::TripleO::Services::NovaApi: OS::Heat::None
  OS::TripleO::Services::NovaConductor: OS::Heat::None
  OS::TripleO::Services::NovaConsoleauth: OS::Heat::None
  OS::TripleO::Services::NovaIronic: OS::Heat::None
  OS::TripleO::Services::NovaMetadata: OS::Heat::None
  OS::TripleO::Services::NovaPlacement: OS::Heat::None
  OS::TripleO::Services::NovaScheduler: OS::Heat::None
  OS::TripleO::Services::NovaVncProxy: OS::Heat::None
  OS::TripleO::Services::OsloMessagingNotify: OS::Heat::None
  OS::TripleO::Services::OsloMessagingRpc: OS::Heat::None
  OS::TripleO::Services::Redis: OS::Heat::None
  OS::TripleO::Services::SwiftProxy: OS::Heat::None
  OS::TripleO::Services::SwiftStorage: OS::Heat::None
  OS::TripleO::Services::SwiftRingBuilder: OS::Heat::None
EOF

export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETMASK=24
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`

tar -xvzf export_control_plane.tar.gz


# Apply change of https://review.opendev.org/#/c/671486/ if not merged yet

sudo openstack tripleo deploy \
    --templates \
    --local-ip=$IP/$NETMASK --local-domain ${DOMAIN:-localdomain} \
    -r /usr/share/openstack-tripleo-heat-templates/roles/Standalone.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/standalone.yaml \
    -e $HOME/containers-prepare-parameters.yaml \
    -e $HOME/standalone_parameters.yaml \
    -e $HOME/standalone_edge.yaml \
    -e $HOME/export_control_plane/passwords.yaml \
    -e $HOME/export_control_plane/endpoint-map.json \
    -e $HOME/export_control_plane/all-nodes-extra-map-data.json \
    -e $HOME/export_control_plane/extra-host-file-entries.json \
    -e $HOME/export_control_plane/oslo.yaml \
    --output-dir $HOME \
    --standalone

