#!/usr/bin/env bash

DIR=export_control_plane
mkdir -p $DIR

unset OS_CLOUD
export OS_AUTH_TYPE=none
export OS_ENDPOINT=http://127.0.0.1:8006/v1/admin

openstack stack output show standalone EndpointMap --format json \
| jq '{"parameter_defaults": {"EndpointMapOverride": .output_value}}' \
> $DIR/endpoint-map.json


openstack stack output show standalone AllNodesConfig --format json \
| jq '{"parameter_defaults": {"AllNodesExtraMapData": .output_value}}' \
> $DIR/all-nodes-extra-map-data.json

openstack stack output show standalone HostsEntry -f json \
| jq -r '{"parameter_defaults":{"ExtraHostFileEntries": .output_value}}' \
> $DIR/extra-host-file-entries.json

cp $HOME/tripleo-undercloud-passwords.yaml $DIR/passwords.yaml


export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETWORK=$(ip r |grep $IP|cut -d" " -f1| tr -d '[[:space:]]')

cat > $DIR/oslo.yaml <<EOF
parameter_defaults:
  NovaAdditionalCell: True
  StandaloneExtraConfig:
    tripleo::firewall::firewall_rules:
      '300 allow ssh access':
        port: 22
        proto: tcp
        destination: $NETWORK
        action: accept
    oslo_messaging_notify_use_ssl: false
    oslo_messaging_rpc_use_ssl: false
EOF

echo "    oslo_messaging_notify_password: $(sudo hiera oslo_messaging_notify_password)" >> $DIR/oslo.yaml
echo "    oslo_messaging_rpc_password: $(sudo hiera oslo_messaging_rpc_password)" >> $DIR/oslo.yaml
echo "    oslo_messaging_notify_short_bootstrap_node_name: $(sudo hiera oslo_messaging_notify_short_bootstrap_node_name)" >> $DIR/oslo.yaml
echo "    oslo_messaging_notify_node_names: $(sudo hiera oslo_messaging_notify_node_names)" >> $DIR/oslo.yaml
echo "    oslo_messaging_rpc_node_names: $(sudo hiera oslo_messaging_rpc_node_names)" >> $DIR/oslo.yaml
echo "    oslo_messaging_rpc_cell_node_names: $(sudo hiera oslo_messaging_rpc_node_names)" >> $DIR/oslo.yaml
echo "    memcached_node_ips: $(sudo hiera memcached_node_ips)" >> $DIR/oslo.yaml
echo "    neutron::agents::ovn_metadata::metadata_host: $(sudo hiera cloud_name_ctlplane)" >> $DIR/oslo.yaml

tar -cvzf export_control_plane.tar.gz export_control_plane

