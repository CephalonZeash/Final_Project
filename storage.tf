resource "proxmox_vm_qemu" "storage" {
  name        = "sto-0"
  vmid        = 200
  target_node = "${var.node_name}"
  desc        = "Storage server for the Kubernetes cluster and endpoint."
  
  clone   = "debian-template" 
  onboot  = true
  # The storage server starts first upon booting the PVE host
  startup = "order=1"

  cpu      = "kvm64"
  cores    = 2
  sockets  = 1
  memory   = 512
  bootdisk = "scsi0"

  disk {
    storage = "${var.disk_storage}"
    format  = "raw"
    type    = "scsi"
    size    = "${var.storage_disk_size}"
  }

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
  ipconfig0               = "ip=${var.storage_ip}/${var.subnet},gw=${var.gateway}"
  
  # remote-exec provisioner for checking the VM's state
  provisioner "remote-exec" {
    connection {
      host        = "${var.storage_ip}"
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
      vm_ip  = "${var.storage_ip}"
    }
    
    # This set of commands runs when the VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $pve_ip, playbooks/pve_vm_conf.yml --extra-vars="vmid=$vmid vm_type=storage"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_storage host_ip=$vm_ip host_state=present"
    EOT
  }
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [
      agent
    ]
  }
}

# This resource ensures the storage server is removed from the inventory in case of destruction
resource "null_resource" "storage-pre-destroy" {
  triggers = {
    vmid       = "${proxmox_vm_qemu.storage.vmid}"
    storage_ip = "${var.storage_ip}"
  }
  
  provisioner "local-exec" {
    when = destroy

    environment = {
      vm_ip = "${self.triggers.storage_ip}"
    }

    command = <<EOT
      ansible-playbook ansible/playbooks/inventory.yml --extra-vars="host_group=storage host_ip=$vm_ip host_state=absent"
    EOT
  }
}
