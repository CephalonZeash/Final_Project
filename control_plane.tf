resource "proxmox_vm_qemu" "control_plane" {
  # Number of Control Planes instances to make
  count = "${var.control_plane_count}"
  
  # The names and VMIDs of instances change according to their index
  name        = "kcp-${count.index}"
  vmid        = "${400 + count.index}"
  target_node = "${var.node_name}"
  desc        = "Kubernetes control plane."

  clone   = "debian-template" 
  onboot  = true
  # Control Planes start after the storage and endpoint servers have started upon booting the PVE host
  startup = "order=3,up=30"

  # All Control Planes share the same resource specification
  cpu      = "kvm64"
  cores    = 2
  sockets  = 1
  memory   = 1536
  bootdisk = "scsi0"

  network {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }
  
  # Cloud-init settings
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "${var.disk_storage}"
  ciuser                  = "root"
  sshkeys                 = "${var.ssh_key}"
  nameserver              = "${var.nameserver}"
  # Network configuration
  ipconfig0               = "ip=${var.network_prefix}${var.control_plane_starting_ip + count.index}/${var.subnet},gw=${var.gateway}"
  
  # remote-exec provisioner for checking the VM's state
  provisioner "remote-exec" {
    connection {
      host        = "${var.network_prefix}${var.control_plane_starting_ip + count.index}"
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
      vm_ip  = "${var.network_prefix}${var.control_plane_starting_ip + count.index}"
    }
    
    # This set of commands runs when the VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $pve_ip, playbooks/pve_vm_conf.yml --extra-vars="vmid=$vmid vm_type=control_plane"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_control_plane host_ip=$vm_ip host_state=present"
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
    proxmox_vm_qemu.endpoint
  ]
}

# This resource ensures control planes are destroyed cleanly
resource "null_resource" "control_plane-pre-destroy" {
  count = "${var.control_plane_count}"

  triggers = {
    vmid           = "${proxmox_vm_qemu.control_plane[count.index].vmid}"
    name           = "${proxmox_vm_qemu.control_plane[count.index].name}"
    storage_ip     = "${var.storage_ip}"
    endpoint_ip    = "${var.endpoint_ip}"
    network_prefix = "${var.network_prefix}"
    control_plane_starting_ip = "${var.control_plane_starting_ip}"
  }
  
  provisioner "local-exec" {
    when = destroy

    environment = {
      name        = "${self.triggers.name}"
      storage_ip  = "${self.triggers.storage_ip}"
      endpoint_ip = "${self.triggers.endpoint_ip}"
      vm_ip       = "${self.triggers.network_prefix}${self.triggers.control_plane_starting_ip + count.index}"
    }

    # Runs a set of cleanup Playbooks and kubectl commands to ensure:
    # - the VM is no longer pointed to by the endpoint
    # - the VM doesn't have permissions to the storage server anymore
    # - the VM doesn't exist in the Inventory
    # - the VM doesn't exist in the Kubernetes cluster
    command = <<EOT
        cd ansible/
        ansible-playbook -i $endpoint_ip, playbooks/endpoint_hosts.yml --extra-vars="host_ip=$vm_ip host_type=control_plane host_name=$name host_state=absent"
        kubectl drain $name --ignore-daemonsets --delete-emptydir-data
        kubectl delete node $name
        ansible-playbook -i $storage_ip, playbooks/storage_hosts.yml --extra-vars="host_ip=$vm_ip host_type=k8s host_state=absent"
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=control_plane host_ip=$vm_ip host_state=absent"
    EOT
  }
}
