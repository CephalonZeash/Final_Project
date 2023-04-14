resource "proxmox_vm_qemu" "endpoint" {
  name        = "enp-0"
  vmid        = 300
  target_node = "${var.node_name}"
  desc        = "Endpoint and load balancer for the Kubernetes cluster."
  
  clone   = "debian-template" 
  onboot  = true
  # The endpoint server starts after the storage server has started upon booting the PVE host
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

  # Cloud-init settings
  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "${var.disk_storage}"
  ciuser                  = "root"
  sshkeys                 = "${var.ssh_key}"
  nameserver              = "${var.nameserver}"
  # Network configuration
  ipconfig0               = "ip=${var.endpoint_ip}/${var.subnet},gw=${var.gateway}"

  # remote-exec provisioner for checking the VM's state
  provisioner "remote-exec" {
    connection {
      host        = "${var.endpoint_ip}"
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
      vm_ip  = "${var.endpoint_ip}"
    }
    
    # This set of commands runs when the VM is running and reachable using SSH.
    # They only prepare the VM for further configuration.
    command = <<EOT
      cd ansible/
      ansible-playbook -i $pve_ip, playbooks/pve_vm_conf.yml --extra-vars="vmid=$vmid vm_type=endpoint"
      ansible-playbook playbooks/inventory.yml --extra-vars="host_group=new_endpoint host_ip=$vm_ip host_state=present"
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

# This resource ensures the endpoint is destroyed cleanly
resource "null_resource" "endpoint-pre-destroy" {
  triggers = {
    vmid        = "${proxmox_vm_qemu.endpoint.vmid}"
    storage_ip  = "${var.storage_ip}"
    endpoint_ip = "${var.endpoint_ip}"
  }                                                           
  provisioner "local-exec" {
    when = destroy

    environment = {
      storage_ip = "${self.triggers.storage_ip}"
      vm_ip      = "${self.triggers.endpoint_ip}"
    }

    # Runs a set of cleanup Playbooks and kubectl commands to ensure:
    # - the VM doesn't have permissions to the storage server anymore
    # - the VM doesn't exist in the Inventory
    command = <<EOT
        cd ansible/
        ansible-playbook -i $storage_ip, -u root playbooks/storage_hosts.yml --extra-vars="host_ip=$vm_ip host_type=endpoint host_state=absent"  
        ansible-playbook playbooks/inventory.yml --extra-vars="host_group=endpoint host_ip=$vm_ip host_state=absent"
    EOT
  }
}
