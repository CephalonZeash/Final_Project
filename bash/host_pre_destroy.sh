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

# Determine which control plane / node is specified
HOST_NUM=$(
    echo $NAME | awk '{
        x = substr($0, 5);
        print x;
    }'
)

# Determine the specified host's IP address
VM_IP=$(
    awk -v type="$HOST_TYPE" -v num="$HOST_NUM" '
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

if [[ $HOST_TYPE == "node" ]]; then
    # Determine which zone the specified node belongs to
    HOST_ZONE=$(
        echo $NAME | awk '{
            x = substr($0, 3, 1);
            print x;
        }'
    )

    # Remove the host from inventory
    if [[ $HOST_ZONE == "a" ]]; then
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=zone_a_node host_ip=$VM_IP host_state=absent"
    elif [[ $HOST_ZONE == "b" ]]; then
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=zone_b_node host_ip=$VM_IP host_state=absent"
    else
        exit 1
    fi
elif [[ $HOST_TYPE == "control_plane" ]]; then
    ansible-playbook playbooks/inventory.yml --extra-vars="host_group=control_plane host_ip=$VM_IP host_state=absent"
else
    exit 1
fi