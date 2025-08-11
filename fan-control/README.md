```markdown
# GPU Fan Control (Unified, IPMI + PWM)

## What This Is
A robust fan control solution that adjusts server fan speeds based on GPU temperature read from dedicated GPU VMs. Features:
- **Dual Backend Support**:
  - `ipmi`: For Dell servers (R720 tested)
  - `pwm`: For consumer hardware (MSI B550 + nct6775 tested)
- **Safety First**:
  - Failsafe (default 100%) on temperature read failures
  - Moderate fallback (60%) on service exit
  - Lockfile prevents multiple instances
- **Dynamic Cooling**:
  - Configurable temperature thresholds
  - Aggressive profile optimized for AI workloads
  - Dry run mode for testing

## Requirements
### Proxmox Host Setup
| Backend | Packages Needed | Notes |
|---------|-----------------|-------|
| `ipmi` | `ipmitool`, `openssh-client` | Dell iDRAC interface |
| `pwm` | `lm-sensors`, `openssh-client` | Load: `modprobe nct6775` |

### GPU VM Setup
- NVIDIA driver with `nvidia-smi`
- Passwordless SSH access from Proxmox host (root recommended)
```bash
# On Proxmox host:
ssh-keygen -t rsa -f /root/.ssh/id_rsa
ssh-copy-id -i /root/.ssh/id_rsa.pub root@[GPU-VM-IP]
```

## Repository Structure
```bash
fan-control/
├── ansible/            # Infrastructure as Code
│   ├── host_vars/
│   │   ├── dellproxmox.yml.example
│   │   └── msiproxmox.yml.example
│   ├── inventory/
│   │   └── hosts.example
│   └── roles/
│       └── fan_control/
│           └── tasks/
│               └── main.yml
├── configs/            # Environment templates
│   ├── dellproxmox.env.example
│   └── msiproxmox.env.example
├── scripts/            # Core logic
│   └── gpu_fan_control.sh.tmpl
├── systemd/            # Service management
│   └── gpu_fan_control.service.tmpl
├── templates/          # Ansible customization
│   ├── gpu_fan_control.sh.j2
│   └── gpu_fan_control.service.j2
├── Makefile            # Deployment helper
└── README.md
```

## Installation Methods

### Method 1: Manual Setup
```bash
# 1. Install script
sudo install -m 0755 scripts/gpu_fan_control.sh.tmpl /usr/local/sbin/gpu_fan_control.sh

# 2. Create config (choose examples below)
sudo nano /etc/default/gpu_fan_control

# 3. Install systemd service
sudo cp systemd/gpu_fan_control.service.tmpl /etc/systemd/system/gpu_fan_control.service
sudo systemctl daemon-reload

# 4. Enable service
sudo systemctl enable --now gpu_fan_control.service
```

### Method 2: Makefile (Recommended)
```bash
cd fan-control
make install     # Interactive installation
make enable      # Enable service
make start       # Start service
make logs        # View live logs
```

### Example Configurations
**Dell R720 (ipmi)** - `/etc/default/gpu_fan_control`:
```ini
BACKEND=ipmi
POLL_SECONDS=5
LOG_PATH=/var/log/gpu_fan_control.log
SSH_HOST=192.0.2.10
SSH_USER=root
SSH_KEY=/root/.ssh/id_rsa
FAN_STEPS="35:40,42:65,48:80,55:100"
IPMI_MAX_HEX=0x64
FAILSAFE_PERCENT=100
EXIT_PERCENT=60
```

**MSI B550 (pwm)** - `/etc/default/gpu_fan_control`:
```ini
BACKEND=pwm
POLL_SECONDS=5
SSH_HOST=192.0.2.20
SSH_USER=root
SSH_KEY=/root/.ssh/id_rsa
FAN_STEPS="35:40,42:65,48:80,55:100"
PWM_PATHS="/sys/devices/platform/nct6775.2592/hwmon/hwmon4/pwm2 /sys/devices/platform/nct6775.2592/hwmon/hwmon4/pwm3"
FAILSAFE_PERCENT=100
EXIT_PERCENT=60
```

## Ansible Deployment
```bash
# 1. Initialize inventory
cp ansible/inventory/hosts.example ansible/inventory/hosts
cp ansible/host_vars/*.yml.example ansible/host_vars/

# 2. Edit host variables
nano ansible/host_vars/dellproxmox.yml
nano ansible/host_vars/msiproxmox.yml  # Add 'pwm_paths' list

# 3. Run playbook
ansible-playbook -i ansible/inventory/hosts -K ansible/site.yml
```

## Operation
### How It Works
1. **Temperature Fetch**:
   ```bash
   ssh -i KEY root@SSH_HOST 'nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits'
   ```
2. **Cooling Curve**:
   `FAN_STEPS="35:40,42:65,48:80,55:100"` means:
   - <35°C → 40%
   - <42°C → 65%
   - <48°C → 80%
   - ≥55°C → 100%

3. **Backend Actions**:
   - `ipmi`: `raw 0x30 0x30 0x01 0x00` (manual) + `0x30 0x30 0x02 0xff HEX`
   - `pwm`: `echo 1 > pwmX_enable` + `echo VALUE > pwmX`

### Troubleshooting Tips
```bash
# Test GPU temp reading:
ssh -i /root/.ssh/id_rsa root@SSH_HOST 'nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader'

# Test PWM fans:
for pwm in /sys/devices/platform/nct*/*/pwm[1-3]; do \
  en="${pwm}_enable"; \
  echo 1 > "$en"; \
  echo 255 > "$pwm"; \
done

# Test IPMI fans:
ipmitool raw 0x30 0x30 0x01 0x00     # Manual mode
ipmitool raw 0x30 0x30 0x02 0xff 0x64  # 100%

# Enable dry run:
echo "DRY_RUN=1" >> /etc/default/gpu_fan_control
systemctl restart gpu_fan_control.service
```

## Portfolio Integration
### Why This Shows Value
1. **Hardware Proficiency**: Direct IPMI/PWM manipulation
2. **Resilience Engineering**: Fail-safe mechanisms
3. **Infrastructure as Code**: Ansible roles + templating
4. **Domain Adaptation**: Custom solutions for consumer and enterprise hardware
5. **Operational Awareness**: Logging, dry runs, safety

### Security Practices
```gitignore
# .gitignore additions
/configs/*.env
/ansible/inventory/hosts
/ansible/host_vars/*.yml
*.pem id_rsa id_ed25519
logs/
```

To maintain privacy: 
- Use RFC5737 addresses (192.0.2.0/24) in docs
- Add `pre-commit` hooks to prevent secret leakage
```bash
#!/bin/sh
# .git/hooks/pre-commit
if git diff --cached --name-only | grep -E 'configs/|inventory/|host_vars/' | grep -v '\.example'; then
  echo "ERROR: Committing secrets is prohibited!" && exit 1
fi
```

---

> View logs: `journalctl -u gpu_fan_control.service -f`
> Contribute: Submit issues/pulls for additional hardware support
```
