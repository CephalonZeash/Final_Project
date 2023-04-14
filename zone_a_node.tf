resource "proxmox_vm_qemu" "zone_a_node" {
  # Number of zone A Node instances to make
  count = "${var.zone_a_node_count}"
  
  # The names and VMIDs of instances change according to their index
  name        = "kza-${count.index}"
  vmid        = "${500 + count.index}"
  target_node = "${var.node_name}"
  desc        = "Kubernetes zone A node."
  
  clone   = "debian-template" 
  onboot  = true
  # Nodes start after all other servers have started upon booting the PVE host
  startup = "order=4,up=30"

  # All Nodes share the same resource specification
  cpu      = "host"
  cores    = 2
  sockets  = 1
  memory   = 2560
  bootdisk = "scsi0"

  network {
    bridge = "vmbr0"
    model = "virtio"
    firewall = true
  }
  
  # Cloud-init settings
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "${var.disk_storage}"
  ciuser                  = "root"
  sshkeys                 = "${var.ssh_key}"
  nameserver              = "${var.nameserver}"
  # Network configuration
  ipconfig0               = "ip=${var.network_prefix}${var.zone_a_node_starting_ip + count.index}/${var.subnet},gw=${var.gateway}"
  
  # remote-exec provisioner for checking the VM's state
  provisioner "remote-exec" {
    connection {
      host        = "${var.network_prefix}${var.zone_a_node_starting_ip + count.index}"
      type        = "ssh"
      user        = "root"
      private_key = file(var.priv_key)
    }

    # Once connected, these commands execute to ensure the VM is ready once Terraform exits
    inline = [
      "sleep 30",
      "echo Done!"
    ]
  }

  provisioner "local-exec" {
    when = create
    
    environment = {
      vmid   = "${self.vmid}"
      pve_ip = "${var.proxmox_ip}"
      vm_ip  = "${var.network_prefix}${var.zone_a_node_starting_ip + count.index}"
    }
    
    # This set of commands runs when the VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $pve_ip, playbooks/pve_vm_conf.yml --extra-vars="vmid=$vmid vm_type=node"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_zone_a_node host_ip=$vm_ip host_state=present"
    EOT
  }

  lifecycle {
    ignore_changes = [
      disk,
      agent
    ]
  }

  depends_on = [
    proxmox_vm_qemu.storage,
    proxmox_vm_qemu.endpoint,
    proxmox_vm_qemu.control_plane
  ]
}

# This resource ensures zone A nodes are destroyed cleanly
resource "null_resource" "zone_a_node_pre_destroy" {
  count = "${var.zone_a_node_count}"

  triggers = {
    vmid                    = "${proxmox_vm_qemu.zone_a_node[count.index].vmid}"
    name                    = "${proxmox_vm_qemu.zone_a_node[count.index].name}"
    storage_ip              = "${var.storage_ip}"
    endpoint_ip             = "${var.endpoint_ip}"
    network_prefix          = "${var.network_prefix}"
    zone_a_node_starting_ip = "${var.zone_a_node_starting_ip}"
  }
  
  provisioner "local-exec" {
    when = destroy

    environment = {
      name        = "${self.triggers.name}"
      storage_ip  = "${self.triggers.storage_ip}"
      endpoint_ip = "${self.triggers.endpoint_ip}"
      vm_ip       = "${self.triggers.network_prefix}${self.triggers.zone_a_node_starting_ip + count.index}"
    }

    # Runs a set of cleanup Playbooks and kubectl commands to ensure:
    # - the VM is no longer pointed to by the endpoint
    # - the VM doesn't have permissions to the storage server anymore
    # - the VM doesn't exist in the Inventory
    # - the VM doesn't exist in the Kubernetes cluster
    command = <<EOT
        cd ansible/
        ansible-playbook -i $endpoint_ip, playbooks/endpoint_hosts.yml --extra-vars="host_ip=$vm_ip host_type=node host_name=$name host_state=absent"
        kubectl drain $name --ignore-daemonsets --delete-emptydir-data
        kubectl delete node $name
        ansible-playbook -i $storage_ip, playbooks/storage_hosts.yml --extra-vars="host_ip=$vm_ip host_type=k8s host_state=absent"
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=zone_a_node host_ip=$vm_ip host_state=absent"
    EOT
  }
}
