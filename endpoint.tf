resource "proxmox_vm_qemu" "endpoint" {
  name        = "enp-0"
  vmid        = 300
  target_node = "pve-01"
  desc        = "Endpoint and load balancer for the Kubernetes cluster."
  
  clone   = "debian-template" 
  onboot  = true
  startup = "order=2,up=30"

  cpu      = "kvm64"
  cores    = 2
  sockets  = 1
  memory   = 1024
  bootdisk = "scsi0"

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
  ipconfig0               = "ip=${var.endpoint_ip}/${var.subnet},gw=${var.gateway}"

  provisioner "remote-exec" {
    connection {
      host        = "${var.endpoint_ip}"
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
      VM_IP  = "${var.endpoint_ip}"
    }
    
    # This set of commands runs when a VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $PVE_IP, playbooks/pve_vm_conf.yml --extra-vars="vmid=$VMID vm_type=endpoint"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_endpoint host_ip=$VM_IP host_state=present"
    EOT
  }

  lifecycle {
    ignore_changes = [
      disk,
      agent
    ]
  }

  depends_on = [
    proxmox_vm_qemu.storage
  ]
}

# This resource ensures the endpoint are destroyed cleanly.
resource "null_resource" "endpoint-pre-destroy" {
  triggers = {
    vmid        = "${proxmox_vm_qemu.endpoint.vmid}"
    storage_ip  = "${var.storage_ip}"
    endpoint_ip = "${var.endpoint_ip}"
  }                                                           
  provisioner "local-exec" {
    when = destroy

    environment = {
      STORAGE_IP = "${self.triggers.storage_ip}"
      VM_IP      = "${self.triggers.endpoint_ip}"
    }

    command = <<EOT
        cd ansible/
        ansible-playbook -i $STORAGE_IP, -u root playbooks/storage_hosts.yml --extra-vars="host_ip=$VM_IP host_type=endpoint host_state=absent"  
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=endpoint host_ip=$VM_IP host_state=absent"
    EOT
  }
}
