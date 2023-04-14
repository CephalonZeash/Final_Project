#!/bin/bash

cd ansible/

read -p "Enter host name: " NAME

# Read endpoint and storage IP values from inventory
ENDPOINT_IP=$(awk '/\[endpoint\]/ { getline; print }' inventory.ini)
STORAGE_IP=$(awk '/\[storage\]/ { getline; print }' inventory.ini)

# Determine whether the host is a Kubernetes node or a Kubernetes control plane
HOST_TYPE=$(
    echo $NAME | awk '{
        x = substr($0, 0, 2);
        if ( x == "kz" ) {
            print "node";
        } else if ( x == "kc" ) {
            print "control_plane";
        }
    }'
)

# Determine which inventory group the host belongs to
HOST_GROUP=$(
   	echo $NAME | awk '{
        x = substr($0, 0, 3);
        if ( x == "kza" ) {
            print "zone_a_node";
        } else if ( x == "kzb" ) {
            print "zone_b_node";
        } else if ( x == "kcp" ) {
            print "control_plane";
        }
    }'
)

# Determine which control plane / node is specified
HOST_NUM=$(
    echo $NAME | awk '{
        x = substr($0, 5);
        print x;
    }'
)

# Determine the specified host's IP address
VM_IP=$(
    awk -v type="$HOST_GROUP" -v num="$HOST_NUM" '
    /network_prefix/ {
        gsub(/"/, "", $3);
        prefix = $3;
    }
    
    $0 ~ type"_starting_ip" {
        gsub(/"/, "", $3);
        ip = prefix "" $3 + num;
        print ip;
    }
    ' ../terraform.tfvars
)

# Remove the host from HAProxy's config
ansible-playbook -i $ENDPOINT_IP, playbooks/endpoint_hosts.yml --extra-vars="host_ip=$VM_IP host_type=$HOST_TYPE host_name=$NAME host_state=absent"

# Remove the host from the cluster
kubectl drain $NAME --ignore-daemonsets --delete-emptydir-data
kubectl delete node $NAME

# Remove the host from NFS's config
ansible-playbook -i $STORAGE_IP, playbooks/storage_hosts.yml --extra-vars="host_ip=$VM_IP host_type=k8s host_state=absent"

# Remove the host from inventory
ansible-playbook playbooks/inventory.yml --extra-vars="host_group=$HOST_GROUP host_ip=$VM_IP host_state=absent"