proxmox_api_url = "https://pve-01.local.domain.com:8006/api2/json"

proxmox_ip = "pve-01.local.domain.com"
node_name  = "pve-01"

priv_key = "~/.ssh/id_rsa"
ssh_key  = "your_pub_key"

storage_disk_size = "32G"
disk_storage      = "local-lvm"

control_plane_count = 3
zone_a_node_count   = 2
zone_b_node_count   = 1

network_prefix            = "10.0.0."
subnet                    = "24"
nameserver                = "10.0.0.1"
gateway                   = "10.0.0.1"
storage_ip                = "10.0.0.200"
endpoint_ip               = "10.0.0.210"
control_plane_starting_ip = "220"
zone_a_node_starting_ip   = "230"
zone_b_node_starting_ip   = "240"
