# Linux APT Simulator

A bash-based adversary simulation tool for Linux that generates **120+ MITRE ATT&CK artifacts** to validate SIEM/EDR detection rules. The Linux equivalent of [APTSimulator](https://github.com/NextronSystems/APTSimulator).

```
  _     _                        _    ____ _____   ____  _           
 | |   (_)_ __  _   ___  __     / \  |  _ \_   _| / ___|(_)_ __ ___  
 | |   | | '_ \| | | \ \/ /   / _ \ | |_) || |   \___ \| | '_ ` _ \ 
 | |___| | | | | |_| |>  <   / ___ \|  __/ | |    ___) | | | | | | |
 |_____|_|_| |_|\__,_/_/\_\ /_/   \_\_|    |_|   |____/|_|_| |_| |_|
```

## Why?

APTSimulator by Nextron Systems is the go-to tool for simulating APT artifacts on Windows, but there's no real equivalent for Linux. If you're running an Elastic SIEM, Wazuh, Splunk, or any other detection stack and you need to validate whether your rules actually catch anything — this tool does exactly that.

No agents, no C2 servers, no complex setup. Just a single bash script that makes your system look compromised.

## Quick Start

```bash

# Run all tests (automated)
sudo bash linux-apt-simulator.sh --auto

# Or pick specific categories via interactive menu
sudo bash linux-apt-simulator.sh
```

## What It Does

The script drops artifacts, creates files, modifies configs, and executes commands that mimic real APT behavior — all mapped to the MITRE ATT&CK framework. Nothing actually connects to a C2 server or causes real damage.

### Coverage

| Tactic | ID | Tests | Examples |
|---|---|---|---|
| Reconnaissance | TA0043 | 3 | Port scanning, software inventory, network topology mapping |
| Initial Access | TA0001 | 3 | Webshell drops (PHP/JSP), cloud credential artifacts, supply chain implant |
| Execution | TA0002 | 8 | Bash/Python/PowerShell, cron jobs, systemd timers, fileless via /dev/shm, ELF dropper |
| Persistence | TA0003 | 14 | Backdoor users, SSH key injection, .bashrc/.profile, systemd services, LD_PRELOAD, MOTD, udev rules, PAM, git hooks, sshd_config |
| Privilege Escalation | TA0004 | 7 | SUID binaries, sudoers backdoor, capabilities abuse, PATH hijack, Docker escape, container recon |
| Defense Evasion | TA0005 | 12 | Log clearing, history evasion, timestomping, masquerading, rootkit indicators, process name spoofing, security tool disable scripts |
| Credential Access | TA0006 | 10 | /etc/shadow dump, credential file search, /proc scraping, SSH agent hijack, cloud metadata theft, Kerberos, database creds |
| Discovery | TA0007 | 11 | Full sysinfo, network connections, security software enum, VM detection, Docker/K8s enum |
| Lateral Movement | TA0008 | 5 | SSH credential spraying, key propagation, Ansible abuse, SCP tool transfer |
| Collection | TA0009 | 5 | Data staging, encrypted archives, auto collector, screen capture, clipboard |
| Command & Control | TA0011 | 9 | C2 domain DNS queries, DNS tunneling, EICAR drops, hacking tool indicators, reverse shells (8 languages), malleable C2 profiles |
| Exfiltration | TA0010 | 4 | Multi-method exfil (HTTP/DNS/NC/SCP/ICMP), AES-256 encryption, cloud storage, steganography |
| Impact | TA0040 | 6 | Ransomware simulation, cryptominer config, data wiper, service disruption, defacement |
| Advanced Tradecraft | Bonus | 13 | memfd_create, ptrace injection, LOLBins, iptables backdoor, container escape, hosts poisoning, kernel param manipulation |

**Total: 120 tests across 14 categories**

## Requirements

- Linux (tested on Ubuntu/Debian, should work on most distros)
- Root access (`sudo`)
- Basic utilities (coreutils, bash, curl/wget)
- Optional: python3, openssl, nmap, docker (some tests gracefully skip if not available)

## Cleanup

Every change the script makes is tracked. A cleanup script is auto-generated at `/tmp/apt-sim-cleanup.sh`:

```bash
sudo bash /tmp/apt-sim-cleanup.sh
```

This reverts all modifications: removes created files, restores modified configs, deletes backdoor users, cleans cron entries, etc.

## Example Output

```
  ┌─────────────────────────────────────────────────────────┐
  │ PERSISTENCE (TA0003)
  └─────────────────────────────────────────────────────────┘

  [15] T1136.001 — Create Account: Backdoor Users
    ✓ Created backdoor users 'apt_backdoor' (root group) and 'svc_update'
  [16] T1136.001 — Create Account: UID 0 User (root-equivalent)
    ✓ Added UID 0 user 'sysbackup' to /etc/passwd
  [17] T1098.004 — SSH Authorized Keys Injection
    ✓ Injected SSH keys into root and all user accounts
  [18] T1546.004 — Shell Profile Backdoors (.bashrc, .profile, /etc/profile.d)
    ✓ Backdoored /root/.bashrc and /etc/profile.d/
```

## Use Cases

- **SIEM Rule Validation** — Run the simulator, check if your Elastic/Splunk/Wazuh rules fire
- **Detection Engineering** — Identify gaps in your detection coverage mapped to ATT&CK
- **SOC Training** — Give analysts realistic alerts to triage in a lab environment
- **Purple Team Exercises** — Blue team validates detection while reviewing red team TTPs
- **Compliance Testing** — Demonstrate detection capabilities for audits

## Tested With

- Elastic SIEM + Elastic Agent (Auditbeat, Filebeat)
- Wazuh
- Splunk + Sysmon for Linux
- Auditd + Laurel

## ⚠️ Disclaimer

**This tool is intended for authorized security testing in lab environments only.**

Do not run this on production systems. The script creates backdoor users, modifies system configurations, drops test files, and simulates malicious activity. While all changes are reversible via the cleanup script, running this outside of a controlled environment could trigger real security alerts and potentially violate organizational policies.

The author assumes no liability for misuse of this tool.

## Acknowledgments

- [APTSimulator](https://github.com/NextronSystems/APTSimulator) by Nextron Systems — the original inspiration (Windows)
- [MITRE ATT&CK](https://attack.mitre.org/) — framework for technique mapping
- [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) — another great adversary emulation resource
- [GTFOBins](https://gtfobins.github.io/) — LOLBins reference for Linux

## License

MIT
