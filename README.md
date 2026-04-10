# Paperless Portal — Self-Hosted Document Management with API Auth & RBAC

A custom web portal built on top of **Paperless-ngx**, featuring API-based authentication and role-based access control (RBAC). Users authenticate directly via the Paperless-ngx API — the portal dynamically adapts its interface based on the authenticated user's role. Deployed locally via **Vagrant + Docker Compose**, then migrated to a **Hostinger cloud VPS**.

---

## What This Is

Paperless-ngx is a powerful self-hosted document management system, but its default interface is a single unified UI with no role differentiation. This project wraps it with a custom portal that:

- Authenticates users through the Paperless-ngx REST API (no separate user database)
- Determines the user's role after authentication
- Renders a different interface and feature set depending on that role
- Keeps all document storage and processing inside the existing Paperless-ngx stack

---

## Architecture
![Architecture diagram](docs/architecture-paperless-portal.svg)
```
Browser
   │
   ▼
[ Custom Web Portal ]  ◄── Role-based UI rendering
   │
   │  API calls (token-based)
   ▼
[ Paperless-ngx API ]
   │
   ├── [ PostgreSQL 15 ]   — document metadata
   ├── [ Redis ]           — task queue / cache
   ├── [ Gotenberg ]       — document conversion
   └── [ Apache Tika ]     — content extraction / OCR
```

All backend services run via **Docker Compose**.

---

## Stack

| Component | Role |
|---|---|
| Paperless-ngx | Document management, OCR, REST API |
| PostgreSQL 15 | Metadata storage |
| Redis | Queue and cache |
| Gotenberg | PDF/document conversion |
| Apache Tika | Content extraction |
| Custom Portal | Auth layer + RBAC frontend |
| Docker Compose | Service orchestration |
| Apache (reverse proxy) | HTTPS termination, routing |

---

## Authentication Flow

```
1. User submits credentials on portal login form
2. Portal sends POST /api/token/ to Paperless-ngx
3. Paperless returns auth token (or 401)
4. Portal fetches user profile via /api/profile/ using the token
5. Role is determined from user group membership
6. Session established — UI rendered based on role
```

No credentials are stored by the portal. Every subsequent API call uses the Paperless token.

---

## Roles

| Role | Access |
|---|---|
| `admin` | Full document access, user overview, all tags/correspondents |
| `operator` | Upload, tag, search documents |
| `viewer` | Read-only access to assigned document sets |

Roles map directly to Paperless-ngx user groups — no separate role configuration needed in the portal.

---

## Local Setup (Vagrant + Docker Compose)

```bash
git clone https://github.com/roysakai/paperless-portal
cd paperless-portal

# Start the VM
vagrant up

# SSH in and start the stack
vagrant ssh
cd /opt/paperless
docker compose up -d

# Portal available at:
# http://192.168.155.10:8081
```

### VM Specs (Vagrant/KVM)

| Setting | Value |
|---|---|
| OS | Ubuntu 22.04 |
| IP | 192.168.155.10 |
| Hypervisor | KVM/Libvirt |
| Paperless port | 8081 |

---

## Cloud Deployment (Hostinger VPS)

After validating the full stack locally, the entire setup was migrated to a Hostinger VPS:

1. Exported PostgreSQL database from local VM
2. Transferred document archive and media volumes
3. Reprovisioned Docker Compose stack on the VPS
4. Configured Apache as reverse proxy with Let's Encrypt SSL
5. Configured systemd service for auto-restart on reboot
6. Validated all functionality post-migration with zero data loss

---

## Environment Variables

Key variables in `.env` (not committed — see `.env.example`):

```env
PAPERLESS_SECRET_KEY=
PAPERLESS_DBPASS=
PAPERLESS_REDIS_URL=redis://redis:6379
PAPERLESS_OCR_LANGUAGE=eng+por
PAPERLESS_TIME_ZONE=America/Sao_Paulo
PORTAL_SESSION_SECRET=
```

---

## OCR Configuration

Configured for bilingual OCR:

```
PAPERLESS_OCR_LANGUAGE=eng+por
```

Supports English and Brazilian Portuguese documents out of the box.

---

## Project Context

Built as a personal homelab project to explore Docker Compose orchestration, REST API integration, session-based auth, and RBAC — and to solve a real usability gap in Paperless-ngx's default interface. The full lifecycle — local development → validation → cloud migration — was completed in a single sprint.

---

## License

MIT

## 🚀 One‑command deployment on AWS Free Tier

This template provisions an EC2 `t2.micro` instance (Free Tier eligible) and deploys the Paperless portal with Docker, reverse proxy, and optional SSL.

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (>= 1.0)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (>= 2.9)
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials (or use environment variables)
- An SSH key pair (`~/.ssh/id_rsa.pub` by default)

### Deployment Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/roysakai/paperless-portal.git
   cd paperless-portal/terraform

2. Configure Terraform variables
   Copy terraform.tfvars.example to terraform.tfvars and edit:

   - aws_region – e.g., us-east-1

   - ami_id – find the latest Ubuntu 22.04 LTS AMI (see instructions above)

   - ssh_public_key_path – path to your public key

3. Run Terraform


   $ terraform init
   $ terraform apply -auto-approve

This creates the EC2 instance, security group, VPC, and an Elastic IP. The output will show the public IP.

4. Update Ansible inventory
   Edit ../ansible/inventory/production.ini and replace <public_ip> with the IP from Terraform output.

5. Run Ansible playbook

   $ cd ../ansible
   $ ansible-playbook -i inventory/production.ini playbook.yml -e "domain=yourdomain.com"
(If you don't have a domain, omit the -e "domain=..." and the playbook will configure HTTP only.)

6. Access your Paperless portal
   Open http://<public_ip> or https://yourdomain.com in a browser.


### Troubleshooting & Production Notes
# Paperless‑portal – Production Deployment on AWS

This project deploys [Paperless‑ngx](https://docs.paperless-ngx.com/) with a custom portal, Docker Compose, Apache reverse proxy, Let’s Encrypt SSL, and full infrastructure as code (Terraform + Ansible).

## 🧠 Lessons Learned & Real‑World Fixes

During development and testing on AWS Free Tier, several production‑grade issues were identified and resolved. These are documented below to help others avoid the same pitfalls.

### 1. AWS Free Tier Instance Type – `t3.micro` is not enough

- **Problem:** `t3.micro` (1 GB RAM) caused the Linux OOM killer to terminate SSM agent, SSH daemon, and eventually the network stack after deploying Paperless + PostgreSQL + Redis + Apache.
- **Symptom:** SSH hangs, SSM offline, console freeze.
- **Fix:** Switch to `t3.small` (2 GB RAM) – still free tier for accounts created after July 2025. Also added a **1 GB swap file** in user‑data as a safety net.

**User‑data snippet:**
```bash
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 2. SSH Key Pair Issues
Problem 1: Duplicate key name – Terraform tried to recreate an existing key.

Fix: Use random_id to generate unique key names.

Problem 2: AWS rejected 4096‑bit RSA keys (max 2048 bits).

Fix: Generate a 2048‑bit RSA key: ssh-keygen -t rsa -b 2048.

### 3. EC2 Systems Manager (SSM) Agent Not Starting
Problem: snap install amazon-ssm-agent does not create a systemd service named amazon-ssm-agent.service. Trying to enable it caused user‑data script to fail.

Fix: Remove the systemctl enable line – snap services start automatically. Also attach IAM role AmazonSSMManagedInstanceCore to the instance.

### 4. Ansible – Missing Python Docker Module
Error: ModuleNotFoundError: No module named 'docker'

Fix: Add pip task to install docker Python package before using docker_compose module.

### 5. Ansible – docker-compose vs docker compose
Error: No module named 'compose' when using community.docker.docker_compose.

Fix: Use command: docker compose up -d (Compose V2, already installed via docker-compose-plugin).

### 6. Apache Configuration – Circular Dependency with Certbot
Problem: Certbot fails if the Apache config already contains SSL directives pointing to missing certificates.

Fix: Deploy a HTTP‑only virtual host first, run certbot (which automatically adds SSL and redirects), then optionally fix any leftover port mismatches.

### 7. Certbot – Domain Validation Timeout
Problem: Let’s Encrypt could not reach http://domain/well-known/acme-challenge/ because DNS was not updated or port 80 was closed.

Fix: Ensure DNS A record points to the EC2 public IP and security group allows inbound TCP/80. For DuckDNS, use the update API.

### 8. Backend Port Mismatch (8000 vs 8081)
Problem: Paperless Docker Compose exposed port 8081:8000, but Apache proxy was hardcoded to localhost:8000. HTTPS virtual host (created by certbot) inherited the wrong port.

Symptom: HTTP worked (301 redirect), HTTPS returned “Service Unavailable”.

Fix:

Use an Ansible variable paperless_backend_port (default 8081) in the HTTP template.

After certbot runs, add a replace task that updates the SSL virtual host from localhost:8000 to localhost:8081.

Ansible task:
yaml
- name: Fix backend port in SSL virtual host
  replace:
    path: /etc/apache2/sites-available/paperless-le-ssl.conf
    regexp: 'localhost:8000'
    replace: 'localhost:{{ paperless_backend_port | default(8081) }}'

### 9. Ansible Inventory – Spaces in SSH Key Path
Error: host_list declined parsing production.ini because the path to the SSH key contained spaces and special characters.

Fix: Quote the path or move the key to a path without spaces (e.g., ~/.ssh/paperless-key).

### 10. Deprecation Warning – List of Dictionaries for vars
Warning: Specifying a list of dictionaries for vars is deprecated

Fix: Change vars: - key: value to vars: key: value in all Ansible YAML files.

✅ Current Production State
Instance: t3.small (2 GB RAM) + 1 GB swap

OS: Ubuntu 22.04

Paperless‑ngx: running on http://localhost:8081

Apache: reverse proxy with automatic HTTPS (Let’s Encrypt)

Monitoring: Docker health checks, Apache logs

Backup: (optional – you can add a cron job for pg_dump)

🚀 One‑Command Deployment

cd terraform
terraform apply -auto-approve
cd ../ansible
ansible-playbook -i inventory/production.ini playbook.yml -e "domain=yourdomain.com"

After ~5 minutes, your Paperless portal is live at https://yourdomain.com.


🧰 Repository Structure
text
paperless-portal/
├── terraform/            # VPC, EC2, security group, IAM role
├── ansible/              # Playbooks for Docker, Paperless, Apache, SSL
├── docker-compose.yml    # Paperless + PostgreSQL + Redis + gotenberg + tika
├── .env.example          # Environment variables (secret key, etc.)
└── README.md             # This file

🤝 Contributing / Support
If you encounter any of the issues listed above, please check the troubleshooting section first. For custom deployments or consulting, contact me via Fiverr Pro.