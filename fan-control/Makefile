PREFIX = /usr/local
BIN = $(PREFIX)/sbin/gpu_fan_control.sh
ENV = /etc/default/gpu_fan_control
SERVICE = /etc/systemd/system/gpu_fan_control.service
SERVICETMPL = systemd/gpu_fan_control.service.tmpl

install: 
    install -d -m 755 $(PREFIX)/sbin
    install -m 0755 scripts/gpu_fan_control.sh.tmpl $(BIN)
    @echo "Select configuration:"
    @echo "1. dellproxmox (Dell R720 IPMI)"
    @echo "2. msiproxmox (MSI B550 PWM)"
    @read -p "Choose [1-2]: " choice; \
    case $$choice in \
        1) install -m 0640 configs/dellproxmox.env.example $(ENV) ;; \
        2) install -m 0640 configs/msiproxmox.env.example $(ENV) ;; \
        *) echo "Invalid choice"; exit 1 ;; \
    esac
    sed 's|/etc/default/gpu_fan_control|$(ENV)|' $(SERVICETMPL) > $(SERVICE)
    systemctl daemon-reload
    @echo "Service installed. Edit $(ENV) and run: make enable"

enable:
    systemctl enable gpu_fan_control.service

start:
    systemctl start gpu_fan_control.service

status:
    systemctl status gpu_fan_control.service --no-pager

logs:
    tail -f /var/log/gpu_fan_control.log

uninstall:
    -systemctl disable --now gpu_fan_control.service
    rm -f $(BIN) $(ENV) $(SERVICE)
    systemctl daemon-reload
