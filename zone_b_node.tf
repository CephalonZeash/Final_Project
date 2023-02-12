resource "proxmox_vm_qemu" "zone_b_node" {
  count = "${var.zone_b_node_count}"
  
  name        = "kzb-${count.index}"
  vmid        = "${600 + count.index}"
  target_node = "pve-01"
  desc        = "Kubernetes zone B node."
  
  clone   = "debian-template" 
  onboot  = true
  startup = "order=4,up=30"

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
  
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "local"
  ciuser                  = "root"
  sshkeys                 = "${var.ssh_key}"
  nameserver              = "${var.nameserver}"
  ipconfig0               = "ip=${var.network_prefix}${var.zone_b_node_starting_ip + count.index}/24,gw=${var.gateway}"
  
  provisioner "remote-exec" {
    connection {
      host        = "${var.network_prefix}${var.zone_b_node_starting_ip + count.index}"
      type        = "ssh"
      user        = "root"
      private_key = file(var.priv_key)
    }

    inline = [
      "sleep 30",
      "echo Done!"
    ]
  }

  provisioner "local-exec" {
    when = create
    
    environment = {
      VMID   = "${self.vmid}"
      PVE_IP = "${var.proxmox_ip}"
      VM_IP  = "${var.network_prefix}${var.zone_b_node_starting_ip + count.index}"
    }
    
    # This set of commands runs when a VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $PVE_IP, playbooks/pve_vm_conf.yml --extra-vars="vmid=$VMID vm_type=node"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_zone_b_node host_ip=$VM_IP host_state=present"
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

# This resource ensures zone B nodes are destroyed cleanly.
resource "null_resource" "zone_b_node_pre_destroy" {
  count = "${var.zone_b_node_count}"

  triggers = {
    vmid                    = "${proxmox_vm_qemu.zone_b_node[count.index].vmid}"
    name                    = "${proxmox_vm_qemu.zone_b_node[count.index].name}"
    storage_ip              = "${var.storage_ip}"
    endpoint_ip             = "${var.endpoint_ip}"
    network_prefix          = "${var.network_prefix}"
    zone_b_node_starting_ip = "${var.zone_b_node_starting_ip}"
  }
  
  provisioner "local-exec" {
    when = destroy

    environment = {
      NAME        = "${self.triggers.name}"
      STORAGE_IP  = "${self.triggers.storage_ip}"
      ENDPOINT_IP = "${self.triggers.endpoint_ip}"
      VM_IP       = "${self.triggers.network_prefix}${self.triggers.zone_b_node_starting_ip + count.index}"
    }

    command = <<EOT
        cd ansible/
        ansible-playbook -i $ENDPOINT_IP, playbooks/endpoint_hosts.yml --extra-vars="host_ip=$VM_IP host_type=node host_name=$NAME host_state=absent"
        kubectl drain $NAME --ignore-daemonsets --delete-emptydir-data
        kubectl delete node $NAME
        ansible-playbook -i $STORAGE_IP, playbooks/storage_hosts.yml --extra-vars="host_ip=$VM_IP host_type=k8s host_state=absent"
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=zone_b_node host_ip=$VM_IP host_state=absent"
    EOT
  }
}
