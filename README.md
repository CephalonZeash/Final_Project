# Final_Project
Virtualized Kubernetes cluster using IAC tools Ansible and Terraform

# Setup

## Network preparation

- Open ports 80, 443 and 51820 on your firewall
- Have a domain ready (this example uses Namecheap, check ansible/roles/endpoint/tasks/ddclient.yml for more info)

## Admin PC preparation

- Ensure you have Ansible, Terraform, an SSH client, kubectl, kubens and helm installed
- All done on Kali GNU/Linux Rolling, but any Linux distro will do
- Generate ssh key pair:

```bash
ssh-keygen -t rsa -b 4096
```

- This key will be used throughout the installation

- All role directories should have an empty vars/ directory

## Installing Proxmox VE

### Installing Debian 11 Bullseye

- Download the latest Debian 11 stable release ISO
- Use **Balena Etcher** to flash ISO to USB
- Reboot, change boot order in BIOS and reboot again
- Proceed with installation
- Edit var files for Terraform, Ansible and Kubernetes and add/edit:
	- users
	- passwords
	- ssh keys
	- ip addresses
	- network interfaces
	- other network settings (gateway, dns, subnet, namespaces, ...)
	- service versions (HAProxy, Wireguard, K3s, etc.)
- Enable root ssh login on the host
- Add PVE instance to Ansible inventory
- Run the PVE installation playbook:

```bash
ansible-playbook -i ansible/inventory.ini --ask-pass --ask-vault-pass ansible/playbooks/pve.yml
```

- Create an API token for Terraform and add it to your environment variables

## VM creation and configuration

- Run VM template playbook:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/vm_template.yml
```

- Apply the Terraform module to create base VMs

```bash
terraform init
```

```bash
terraform apply
```

- Run VM configuration playbook to configure all of the VMs

```bash
ansible-playbook -i ansible/inventory.ini --ask-vault-pass ansible/playbooks/vm_conf.yml
```

## Kubernetes configuration

Run all of these commands:

```
kubectl create ns cert-manager
kubectl create ns oc
kubectl create ns mysql-operator
```

```
kubectl apply -f kubernetes/nfs-subdir-provisioner
kubectl apply -f kubernetes/descheduler
```

```
kubectl apply -f kubernetes/cert-manager.yml
```

Then wait for cert-manager to get up and running.

```
kubectl apply -f kubernetes/letsencrypt.yml
```

```
kubens oc
kubectl apply -f kubernetes/mysql-operator/deploy-crds.yml
kubectl apply -f kubernetes/mysql-operator/deployment.yml
kubectl apply -f kubernetes/mysql.yml
```

Finally, once the entire InnoDB cluster is ready, apply the Online C# Compiler's files:

```
kubectl apply -f kubernetes/oc
```

- Get Wireguard peer configs from the endpoint using the wg_peer_info.sh script for remote administration
