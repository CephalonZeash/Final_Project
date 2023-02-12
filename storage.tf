resource "proxmox_vm_qemu" "storage" {
  name        = "sto-0"
  vmid        = 200
  target_node = "pve-01"
  desc        = "Storage server for the Kubernetes cluster and endpoint."
  
  clone   = "debian-template" 
  onboot  = true
  startup = "order=1"

  cpu      = "kvm64"
  cores    = 2
  sockets  = 1
  memory   = 512
  bootdisk = "scsi0"

  disk {
    volume  = "local:200/vm-200-disk-0.qcow2"
    storage = "local"
    format  = "qcow2"
    type    = "scsi"
    size    = "${var.storage_disk_size}"
  }

  network {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "local"
  ciuser                  = "root"
  sshkeys                 = "${var.ssh_key}"
  nameserver              = "${var.nameserver}"
  ipconfig0               = "ip=${var.storage_ip}/${var.subnet},gw=${var.gateway}"
  
  provisioner "remote-exec" {
    connection {
      host        = "${var.storage_ip}"
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
      VM_IP  = "${var.storage_ip}"
    }
    
    # This set of commands runs when a VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $PVE_IP, playbooks/pve_vm_conf.yml --extra-vars="vmid=$VMID vm_type=storage"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_storage host_ip=$VM_IP host_state=present"
    EOT
  }
  
  lifecycle {
    prevent_destroy = false
    ignore_changes  = [
      agent
    ]
  }
}

# This resource ensures the storage server is removed from the inventory in case of destruction.
resource "null_resource" "storage-pre-destroy" {
  triggers = {
    vmid       = "${proxmox_vm_qemu.storage.vmid}"
    storage_ip = "${var.storage_ip}"
  }
  
  provisioner "local-exec" {
    when = destroy

    environment = {
      VM_IP = "${self.triggers.storage_ip}"
    }

    command = <<EOT
      ansible-playbook ansible/playbooks/inventory.yml --extra-vars="host_group=storage host_ip=$VM_IP host_state=absent"
    EOT
  }
}
