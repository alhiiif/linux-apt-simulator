# Linux APT Simulator v3.0

A bash-based adversary simulation tool for Linux that generates **250+ real process events** mapped to the full MITRE ATT&CK Enterprise framework — designed to validate SIEM/EDR detection rules without any external infrastructure.

```
  _     _                        _    ____ _____   ____  _           
 | |   (_)_ __  _   ___  __     / \  |  _ \_   _| / ___|(_)_ __ ___  
 | |   | | '_ \| | | \ \/ /   / _ \ | |_) || |   \___ \| | '_ ` _ \ 
 | |___| | | | | |_| |>  <   / ___ \|  __/ | |    ___) | | | | | | |
 |_____|_|_| |_|\__,_/_/\_\ /_/   \_\_|    |_|   |____/|_|_| |_| |_|
```

## Why?

APTSimulator by Nextron Systems is the go-to tool for simulating APT artifacts on Windows, but there is no real equivalent for Linux. If you run Elastic SIEM, Wazuh, Splunk, or any other detection stack and need to validate whether your rules actually catch anything — this tool does exactly that.

No agents, no C2 servers, no complex setup. One bash script that makes your system look compromised — every test executes real syscalls, real process events, real file events that trigger actual SIEM alerts.

---

## Quick Start

```bash
# Interactive menu (recommended)
sudo bash linux-apt-simulator.sh

# Run all modules (non-interactive)
sudo bash linux-apt-simulator.sh --auto
```

---

## What's New in v3.0

| Feature | Detail |
|---|---|
| **27 standalone modules** | Full MITRE ATT&CK coverage across all 12 enterprise tactics |
| **6 attack chains** | Multi-stage realistic scenarios (APT-29, LockBit, Lazarus, TeamTNT, UNC2452, APT41) |
| **Terminal animations** | Matrix rain intro, braille spinners, typewriter headers, animated progress bar |
| **JSON + HTML reports** | Auto-generated after every run with pass/fail stats and tactic coverage |
| **Fileless execution** | `memfd_create`, `/proc/self/fd` exec, LD_PRELOAD injection |
| **Container escape** | nsenter, Docker socket abuse, cgroup release_agent, unshare |
| **Supply chain** | pip/npm typosquatting, git hook poisoning, malicious setup.py |
| **Cloud credentials** | AWS/GCP/Azure/K8s/Docker config file access |
| **Extended C2** | ICMP tunnel, non-standard ports, TLS, GitHub/Slack/Discord dead-drop, DoH, Cobalt Strike Malleable C2 pattern |

---

## Coverage — 27 Modules

### Core MITRE ATT&CK Tactics

| Module | Tactic | ID | Key Techniques |
|---|---|---|---|
| Initial Access | TA0001 | T1566/T1190/T1195 | Phishing lure drop, web shell upload, exploit UA, archive with payload |
| Execution | TA0002 | T1059/T1053/T1543 | bash/python/perl shell, base64 pipe, /dev/shm exec, cron, systemd timer, curl\|bash |
| Persistence | TA0003 | T1136/T1547/T1543 | Backdoor user, UID-0 account, SSH key, bashrc/profile.d, systemd service, cron.d, LD_PRELOAD, udev, MOTD, init.d |
| Privilege Escalation | TA0004 | T1548/T1068/T1055 | SUID/SGID, sudoers, setcap, sysctl ptrace_scope |
| Defense Evasion | TA0005 | T1562/T1070/T1036 | Firewall flush, auditd stop, history clear, timestomping, shred, log truncation, masquerade, chattr, journal vacuum |
| Credential Access | TA0006 | T1003/T1110/T1552 | shadow/passwd/gshadow, SSH key harvest, /proc/mem dump, PAM backdoor, brute force sim, strace, cloud IMDS |
| Discovery | TA0007 | T1082/T1083/T1046 | Sysinfo, network config, connections, process, account, security tool, VM detect, Docker/K8s, mounted shares |
| Lateral Movement | TA0008 | T1021/T1570/T1550 | SSH sweep, SCP, ssh-keyscan, keygen, rsync, smbclient/rpcclient, xargs parallel SSH |
| Collection | TA0009 | T1005/T1074/T1560 | Data staging, tar/zip archive, clipboard, screen capture |
| Command & Control | TA0011 | T1071/T1095/T1571 | DNS C2, DNS tunneling, EICAR, hacking tool names, bash/python/nc reverse shell, socat, port scan, curl beacon |
| Exfiltration | TA0010 | T1041/T1048/T1020 | curl POST, DNS chunked, openssl encrypt, netcat |
| Impact | TA0040 | T1486/T1485/T1491 | Ransomware rename, service stop, fake xmrig, hosts poisoning, dd wipe, pkill |

### Extended Modules

| Module | Technique | What It Tests |
|---|---|---|
| Fileless / In-Memory | T1055/T1620 | `memfd_create`, `/proc/self/fd` exec, LD_PRELOAD, `exec(base64)`, bash heredoc, `dd` pipe |
| Process Injection | T1055 | ptrace via Python ctypes, gdb attach, `/proc/PID/mem` write, `/proc/self/exe` copy |
| Network Sniffing | T1040 | tcpdump, tshark, promiscuous mode, ARP poisoning, AF_PACKET raw socket |
| Input Capture | T1056 | strace keyboard snoop, /dev/pts TTY read, xinput, readline hook, `script` recording |
| Unsecured Credentials | T1552 | AWS/GCP/Azure/K8s/Docker config, `.env`, git-credentials, token sweep |
| Discovery Extended | T1083/T1069/T1135/T1018/T1518 | File discovery, group enum, NFS/SMB shares, ping sweep, service enum, package list |
| C2 Protocols Extended | T1095/T1571/T1573/T1102/T1001 | ICMP tunnel, non-standard ports (31337/1337/4444), TLS OpenSSL, GitHub/Slack/Discord C2, DoH, XOR obfuscation, Cobalt Strike/Sliver pattern |
| Exfiltration Extended | T1020/T1048/T1029 | FTP, SCP/SFTP, SMTP, automated loop, scheduled cron exfil, steganography, ICMP payload |
| Impact Extended | T1490/T1491/T1498/T1485 | Backup removal, GRUB recon, web defacement, hping3 SYN flood, bulk overwrite |
| Lateral Tool Transfer | T1570 | curl+chmod, SCP push, nc pipe transfer, tool staging dir, python HTTP server, rsync |
| Account Manipulation | T1098 | Group add (sudo/docker/wheel), SSH keys all users, chpasswd, chage, faillock reset |
| Boot/Logon Persistence | T1547 | rc.local, XDG autostart, logrotate hook, systemd path unit, trap EXIT, at job |
| Exploitation Indicators | T1068/T1203/T1190 | Dirty Pipe/PwnKit/Baron Samedit fingerprint, kernel security config read, exploit compile, /proc/kallsyms |
| Container / K8s Escape | T1611 | Docker socket abuse, nsenter PID 1, cgroup release_agent, K8s service account token, unshare |
| Supply Chain | T1195/T1072 | pip/npm typosquatting, pip from evil URL, malicious setup.py, git core.hooksPath poison |

---

## Attack Chains

Access via **[U] ATTACK CHAINS** from the main menu. Each chain simulates a specific threat actor's full kill chain with stage-by-stage narration.

```
  ╔══════════════════════════════════════════════════════════════╗
  ║  CHAIN  : FULL APT KILL CHAIN                               ║
  ║  Actor  : APT-29 / Cozy Bear                                ║
  ║  Scenario: Spearphishing → foothold → persist → pivot → exfil ║
  ╚══════════════════════════════════════════════════════════════╝

  ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
  ◆ STAGE 1 │ INITIAL ACCESS   TA0001 T1566/T1190
  ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
```

| Chain | Threat Actor | Stages | Key Techniques |
|---|---|---|---|
| **Full APT Kill Chain** | APT-29 / Cozy Bear | 11 | Phishing → Exec → Persist → PrivEsc → Evade → Cred → Recon → LM → Collect → C2 → Exfil |
| **Ransomware Deployment** | LockBit 3.0 / BlackCat | 6 | Brute force → Discovery → Disable AV+FW → Remove backups → Lateral spread → AES-256 encrypt |
| **Credential Theft + Pivot** | Lazarus Group / APT38 | 5 | Phishing macro → memfd fileless → Shadow/SSH/env dump → AWS/GCP/K8s creds → SSH pivot |
| **Cryptominer** | TeamTNT / WatchDog | 6 | Docker socket → /dev/shm download → Cron+systemd persist → kworker masquerade → Pool connect |
| **Supply Chain Backdoor** | UNC2452 / SolarWinds | 6 | pip SUNBURST-style → git hook → memfd implant → systemd 14400s dwell → SUNBURST DNS pattern |
| **Stealth Data Exfiltration** | APT41 / Double Dragon | 4 | DB recon → hidden staging → Timestomp → DNS+HTTPS+ICMP+scheduled exfil |

---

## Animations

The script features a full terminal animation engine:

| Animation | When | Description |
|---|---|---|
| Matrix rain | Startup / chain start | Katakana + hex characters falling, green gradient |
| ASCII art slide-in | Startup | Logo lines appear one by one |
| Typewriter | Headers, summary | Characters print one at a time |
| Braille spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` | Every test | Runs in background while test executes, cleared on result |
| Section header typewriter | Each module | Title types into the box character by character |
| Animated counter | Summary | Total/Passed/Failed counts up from 0 |
| Progress bar `█░` | Summary | Green fill proportional to pass rate |
| Launch banner | Menu selection | `▶ Launching: <module>` + animated divider |

---

## Reports

After every run (or single module), two report files are auto-generated:

- **`/tmp/apt-sim-report-<timestamp>.json`** — Machine-readable, ingestable into Elastic/Splunk
- **`/tmp/apt-sim-report-<timestamp>.html`** — Human-readable with dark-theme table, pass/fail bar

---

## Menu Overview

```
  [0]  RUN ALL  (full ATT&CK coverage)

  ── Core Tactics ───────────────────────────────────────────
  [1]  Initial Access              TA0001  T1190/T1566/T1195
  [2]  Execution                   TA0002  T1059/T1053/T1543
  [3]  Persistence                 TA0003  T1136/T1547/T1098
  [4]  Privilege Escalation        TA0004  T1548/T1055/T1068
  [5]  Defense Evasion             TA0005  T1562/T1070/T1036
  [6]  Credential Access           TA0006  T1003/T1110/T1552
  [7]  Discovery                   TA0007  T1082/T1083/T1046
  [8]  Lateral Movement            TA0008  T1021/T1570/T1550
  [9]  Collection                  TA0009  T1005/T1056/T1560
  [A]  Command & Control           TA0011  T1071/T1095/T1571
  [B]  Exfiltration                TA0010  T1041/T1048/T1020
  [C]  Impact                      TA0040  T1486/T1485/T1491

  ── Extended Modules ───────────────────────────────────────
  [E]  Fileless / In-Memory        T1055/T1620
  [F]  Process Injection           T1055
  [G]  Network Sniffing            T1040
  [H]  Input Capture               T1056
  [I]  Unsecured Credentials       T1552
  [J]  Discovery Extended          T1083/T1069/T1135/T1018/T1518
  [K]  C2 Protocols Extended       T1095/T1571/T1573/T1102/T1001
  [L]  Exfiltration Extended       T1020/T1048/T1029
  [M]  Impact Extended             T1490/T1491/T1498/T1485
  [N]  Lateral Tool Transfer       T1570
  [O]  Account Manipulation        T1098
  [P]  Boot/Logon Persistence      T1547
  [Q]  Exploitation Indicators     T1068/T1203
  [R]  Container / K8s Escape      T1611
  [S]  Supply Chain                T1195/T1072
  [T]  Advanced Tradecraft

  ── Attack Chains ──────────────────────────────────────────
  [U]  ATTACK CHAINS               (APT-29 / LockBit / Lazarus / TeamTNT / UNC2452 / APT41)

  [D]  Disable Security Tools      (standalone — NOT in RUN ALL)
```

---

## Requirements

**Required:**
- Linux (tested on Ubuntu 20.04/22.04/24.04, Debian, RHEL/CentOS, Kali)
- Root / sudo access
- bash 4+, coreutils, curl or wget

**Optional** (some tests gracefully skip if unavailable):

| Tool | Used by |
|---|---|
| `python3` | Fileless execution, memfd_create, ptrace, reverse shell |
| `openssl` | Encrypted exfil, archive encryption |
| `nmap` | Port scanning |
| `tcpdump` / `tshark` | Network sniffing module |
| `gcc` | Exploit compilation |
| `gdb` | Process injection |
| `docker` | Container escape |
| `kubectl` | K8s escape |
| `strace` | Input capture, credential snooping |
| `hping3` | DoS indicators |
| `at` | Scheduled job persistence |
| `smbclient` / `rpcclient` | SMB lateral movement |
| `xinput` / `xdotool` | X11 input capture |

---

## Cleanup

Every change the script makes is tracked in a generated cleanup script:

```bash
sudo bash /tmp/apt-sim-cleanup.sh
```

This reverts all modifications: removes created files, restores modified configs, deletes backdoor users, cleans cron entries, reverts sshd_config, restores bashrc, removes systemd services, etc.

---

## Use Cases

- **SIEM Rule Validation** — Run the simulator, check if your Elastic/Splunk/Wazuh rules fire
- **Detection Engineering** — Identify gaps in detection coverage across all ATT&CK tactics
- **SOC Training** — Give analysts realistic multi-stage alerts to triage in a lab environment
- **Purple Team Exercises** — Blue team validates detection while red team reviews TTPs
- **Attack Chain Simulation** — Run named threat actor scenarios end-to-end
- **Compliance Testing** — Demonstrate detection capability for audits

---

## Tested With

- Elastic SIEM + Elastic Agent (Auditbeat, Filebeat, Elastic Defend)
- Wazuh
- Splunk + Sysmon for Linux
- Auditd + Laurel

---

## ⚠️ Disclaimer

**This tool is for authorized security testing in lab/test environments only.**

Do not run this on production systems. The script creates backdoor users, modifies system configurations, drops test files, simulates malicious activity, and intentionally triggers SIEM alerts. All changes are reversible via the cleanup script, but running outside a controlled environment could violate organizational policies and trigger real incident response.

Use only on systems you own or have explicit written authorization to test.

The author assumes no liability for misuse of this tool.

---

## Acknowledgments

- [APTSimulator](https://github.com/NextronSystems/APTSimulator) by Nextron Systems — original inspiration (Windows)
- [MITRE ATT&CK](https://attack.mitre.org/) — framework for technique mapping
- [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) — adversary emulation reference
- [GTFOBins](https://gtfobins.github.io/) — Linux LOLBins reference

---

## License

MIT
