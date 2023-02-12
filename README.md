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

- Create `oc` and `cert-manager` namespaces:

```bash
kubectl create ns oc
```

```bash
kubectl create ns cert-manager
```

- Create the NFS storage class

```bash
kubectl apply -f kubernetes/nfs/rbac.yml
```

```
kubectl apply -f kubernetes/nfs
```

- Install cert-manager (here I use yaml manifests templated from the jetstack/cert-manager helm chart):

```bash
kubectl apply -f kubernetes/cert-manager
```

- Create the Letsencrypt cluster issuer:

```bash
kubectl apply -f kubernetes/letsencrypt.yml
```

- Change the current namespace to "oc":

```bash
kubens oc
```

- Deploy the MySQL Kubernetes operator (here I use modified yaml manifests which you can get from MySQL's documentation):

```bash
kubectl apply -f kubernetes/mysql-operator/deploy-crds.yml
```

```bash
kubectl apply -f kubernetes/mysql-operator/deployment.yml
```

- Deploy the InnoDB cluster (here I use modified yaml manifests templated from the mysql-operator/mysql-innodbcluster helm chart):

```bash
kubectl apply -f kubernetes/mysql.yml
```

- Wait for the InnoDB cluster
- Apply the online compiler manifests:

```bash
kubectl apply -f kubernetes/oc
```

- Get Wireguard peer configs from the endpoint using the wg_peer_info.sh script for remote administration

# Literature (incomplete)
- https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_11_Bullseye
- https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/
- https://www.balena.io/etcher/
- https://cdimage.debian.org/cdimage/cloud/
- https://docs.ansible.com/ansible_community.html
- https://www.terraform.io/downloads
- https://www.terraform.io/docs
- https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
- https://github.com/linuxserver/docker-wireguard
- https://docs.haproxy.org/2.6/configuration.html
- https://www.domstamand.com/adding-haproxy-as-load-balancer-to-the-kubernetes-cluster/
- https://hub.docker.com/_/haproxy
- https://cloud.google.com/docs/terraform/best-practices-for-terraform#module-structure
- https://pve.proxmox.com/wiki/Firewall
- https://www.youtube.com/watch?v=X48VuDVv0do&t=11105s
- https://k3s.io/
- https://medium.com/tailwinds-navigator/kubernetes-tip-how-to-make-kubernetes-react-faster-when-nodes-fail-1e248e184890
- https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
- https://dev.mysql.com/doc/mysql-operator/en/mysql-operator-introduction.html
- https://artifacthub.io/packages/helm/cert-manager/cert-manager
- https://dev.mysql.com/doc/mysql-operator/en/mysql-operator-introduction.html
- https://kubernetes.io/docs/home/
- https://pve.proxmox.com/pve-docs/pveum.1.html
- https://www.namecheap.com/support/knowledgebase/article.aspx/583/11/how-do-i-configure-ddclient/
- https://hub.docker.com/r/linuxserver/ddclient
- https://docs.docker.com/compose/compose-file/compose-file-v3/
