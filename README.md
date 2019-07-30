# tripleo-edge-demo
ansible role for deploying controller compute standalone nodes

### Steps:-
1) Prepare nodes(1 for central node and atleast 1 for edge node),
   these nodes should be accessible without password from local node.
2) Update 'hosts' file with ip address for all these nodes
3) Setup ansible
3) Run: ansible-playbook -i hosts edge-setup.yml
4) Wait for it to complete


# Basically it consist of below shell commands categorized and executed via ansible.

# Create atleast two VMS(8GB each with OS: CentOS7), 1 controller and atleast 1 compute
Node 1(Controller)
```
# Create temporary repo to install tripleo-repos package

sudo tee -a /etc/yum.repos.d/deloreantemp.repo <<EOF
[deloran-temp]
name=delorean-temp
baseurl=https://trunk.rdoproject.org/centos7-master/current
gpgcheck=0
enabled=1
EOF

sudo yum -y install python2-tripleo-repos

sudo rm -rf /etc/yum.repos.d/deloreantemp.repo

# Setup master repos
sudo -E tripleo-repos current-tripleo-dev 

# Install tripleoclient package
sudo yum install -y python2-tripleoclient


# Create 8 GB Swap
sudo dd if=/dev/zero of=/swapfile-additional bs=1M count=8384
sudo mkswap /swapfile-additional
sudo chmod 600 /swapfile-additional
sudo mount -a
sudo swapon -a
sudo swapon -s

# To persist swap on reboot
echo "/swapfile-additional swap swap 0 0" | sudo tee -a /etc/fstab

# Create default container prepare file
openstack tripleo container image prepare default \
  --output-env-file $HOME/containers-prepare-parameters.yaml

# Export Network facts, setup these manually if you dont want to use defaults
sudo yum install -y iproute
export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETMASK=$(ip r |grep $IP|cut -d" " -f1| cut -d/ -f2| tr -d '[[:space:]]')
export GATEWAY=`ip r get 1.1.1.1 | awk '/dev/{print $3}' | tr -d '[[:space:]]'`
export INTERFACE=`ip r get 1.1.1.1 | awk '/dev/{print $5}' | tr -d '[[:space:]]'`
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`
if [ -z $DOMAIN ]; then export DOMAIN=localdomain;fi

# Create standalone config file
cat > $HOME/standalone_parameters.yaml <<EOF
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

# Deploy the central standalone node
# --keep-running is needed so that standalone stack info can be gathered
nohup sudo openstack tripleo deploy \
  --templates \
  --local-ip=$IP/$NETMASK \
  -e /usr/share/openstack-tripleo-heat-templates/environments/standalone/standalone-tripleo.yaml \
  -r /usr/share/openstack-tripleo-heat-templates/roles/Standalone.yaml \
  -e $HOME/containers-prepare-parameters.yaml \
  -e $HOME/standalone_parameters.yaml \
  --output-dir $HOME --local-domain ${DOMAIN:-localdomain}  \
  --standalone --keep-running &
tail -f nohup.out

# Extract Info from deployed central standalone node
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


#logout and copy tarball from Node1 to Node2
scp centos@<node1_ip>:~/export_control_plane.tar.gz .
scp export_control_plane.tar.gz  centos@<node2_ip>:~/

Node 2(Compute)
sudo tee -a /etc/yum.repos.d/deloreantemp.repo <<EOF
[deloran-temp]
name=delorean-temp
baseurl=https://trunk.rdoproject.org/centos7-master/current
gpgcheck=0
enabled=1
EOF

sudo yum -y install python2-tripleo-repos

sudo rm -rf /etc/yum.repos.d/deloreantemp.repo
sudo -E tripleo-repos current-tripleo-dev 
sudo yum install -y python-tripleoclient


sudo dd if=/dev/zero of=/swapfile-additional bs=1M count=8384
sudo mkswap /swapfile-additional
sudo chmod 600 /swapfile-additional
echo "/swapfile-additional swap swap 0 0" | sudo tee -a /etc/fstab
sudo mount -a
sudo swapon -a
sudo swapon -s


openstack tripleo container image prepare default \
  --output-env-file $HOME/containers-prepare-parameters.yaml

sudo yum install -y iproute
export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETMASK=$(ip r |grep $IP|cut -d" " -f1| cut -d/ -f2| tr -d '[[:space:]]')
export GATEWAY=`ip r get 1.1.1.1 | awk '/dev/{print $3}' | tr -d '[[:space:]]'`
export INTERFACE=`ip r get 1.1.1.1 | awk '/dev/{print $5}' | tr -d '[[:space:]]'`
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`
if [ -z $DOMAIN ]; then export DOMAIN=localdomain;fi

cat > $HOME/standalone_parameters.yaml <<EOF
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
  # net config (do not change unless you know what you are doing)
  NeutronBridgeMappings: datacentre:br-ctlplane
  NeutronPhysicalBridge: br-ctlplane
  # enable to force metadata for public net
  #NeutronEnableForceMetadata: true
  StandaloneEnableRoutedNetworks: false
  StandaloneHomeDir: $HOME
  InterfaceLocalMtu: 1450
  # Needed if running in a VM, not needed if on baremetal
  NovaComputeLibvirtType: qemu
EOF

# Disable services which are not needed in edge standalone node
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
export NETMASK=$(ip r |grep $IP|cut -d" " -f1| cut -d/ -f2| tr -d '[[:space:]]')
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`

tar -xvzf export_control_plane.tar.gz


# Apply change of https://review.opendev.org/#/c/671486/ if not merged yet

nohup sudo openstack tripleo deploy \
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
    --standalone &

tail -f nohup.out

# logout and login to Node1(Controller) to register the compute node and create instance on it.

export OS_CLOUD=standalone
openstack hypervisor list
sudo podman exec -it nova_api nova-manage cell_v2 discover_hosts --verbose
openstack hypervisor list

openstack aggregate create HA-edge1 --zone edge1
openstack aggregate add host HA-edge1 standalone-compute.rdocloud

New edge compute node is ready to run vms.

# Steps to create a VM on the setup:-
export OS_CLOUD=standalone

# nova flavor
openstack flavor create --ram 512 --disk 1 --vcpu 1 --public tiny
# basic cirros image
curl -O https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
openstack image create cirros --container-format bare --disk-format qcow2 --public --file cirros-0.4.0-x86_64-disk.img
# nova keypair for ssh
test -f ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
openstack keypair create --public-key ~/.ssh/id_rsa.pub default

# create basic security group to allow ssh/ping/dns
openstack security group create basic
# allow ssh
openstack security group rule create basic --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0
# allow ping
openstack security group rule create --protocol icmp basic
# allow DNS
openstack security group rule create --protocol udp --dst-port 53:53 basic

neutron net-create public --router:external --provider:network_type flat --provider:physical_network datacentre

export GATEWAY=`ip r get 1.1.1.1 | awk '/dev/{print $3}' | tr -d '[[:space:]]'`
export CIDR=`ip r|grep br-ctlplane|cut -d" " -f1|tail -1| tr -d '[[:space:]]'`
neutron subnet-create --name public --enable_dhcp=False --allocation-pool=start=${GATEWAY%.*}.220,end=${GATEWAY%.*}.225 --gateway=$GATEWAY public $CIDR

openstack network create net1
openstack subnet create subnet1 --network net1 --subnet-range 192.0.2.0/24
neutron router-create router1
neutron router-gateway-set router1 public
neutron router-interface-add router1 subnet1
neutron floatingip-create public
netid=$(openstack network show net1 -f value -c id)
floatip=$(openstack floating ip list -f value -c "Floating IP Address"|head -1)
openstack server create --nic net-id=$netid --image cirros --security-group basic --key-name default --flavor tiny testvm
sleep 20
openstack server add floating ip testvm $floatip

# To create Instance on specific availability zone add --availability-zone edge1 to openstack server create like below
openstack server create --nic net-id=$netid --image cirros --security-group basic --key-name default --flavor tiny --availability-zone edge1 testvm_edge1

# Try accessing the VM with floating ip
ping -c 4 cirros@$floatip

ssh cirros@$floatip

``
