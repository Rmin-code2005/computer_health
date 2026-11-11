# 🏆 Computer Health — Your System’s Fitness Check

**Check the stats. Spot the warning signs. Keep your computer in the game.**

Two standalone diagnostic scripts turn system information into readable reports: a full Linux health overview and a focused Windows disk check. Think of them as a pre-match fitness assessment for your machine.

## 🏟️ Pick your arena

| Script | Platform | Game plan | Report location |
| --- | --- | --- | --- |
| `ubuntu_health_report.sh` | Ubuntu / APT-based Linux | System, hardware, and update overview | `~/ubuntu-health-report-YYYYMMDD_HHMMSS.txt` |
| `Check-DiskHealth.ps1` | Windows PowerShell | Disk health and reliability overview | `%USERPROFILE%\Desktop\DiskHealthReport.txt` |

No build step, Python environment, or application server is needed.

## 🐧 Linux: the full fitness assessment

### Warm up

Clone the repository and enter the checkout:

```bash
git clone https://github.com/Rmin-code2005/computer_health.git
cd computer_health
```

Use Bash on Ubuntu or another APT-based Linux distribution. Standard system utilities provide the core report. Optional tools add more detail:

```bash
sudo apt install smartmontools nvme-cli lm-sensors fwupd
```

Installing those tools is optional; unavailable tools are reported in the output. The script also lists `memtester` as an optional diagnostic package, but does not run a memory stress test.

### Kick off

```bash
bash ubuntu_health_report.sh
```

The report appears in the terminal and is saved in your home directory with a timestamp. For privileged hardware checks, review the script first and run with administrator access if appropriate:

```bash
sudo bash ubuntu_health_report.sh
```

When run with `sudo`, the report is saved under the home directory supplied by that sudo session, which may be `/root`. The script prints its output path.

### The scoreboard

The Linux report covers:

- **Engine room:** operating system, CPU, load, temperature, RAM, and swap.
- **Storage squad:** block devices, filesystem space, inodes, SMART status, and NVMe details.
- **Match analysis:** graphics drivers and hardware-related kernel messages.
- **Maintenance bench:** APT updates, Snap and Flatpak update listings, firmware status, and automatic security update configuration.

**The script refreshes APT package indexes when permissions allow, but does not install package, driver, firmware, or BIOS updates.** It also runs an APT upgrade simulation.

## 🪟 Windows: the disk performance check

Open PowerShell in the repository directory, preferably as Administrator for access to available storage diagnostics:

```powershell
.\Check-DiskHealth.ps1
```

The script uses Windows Storage and CIM commands to collect:

- Physical disk identity, media type, bus type, and health status.
- Available storage reliability counters.
- Logical disk capacity and free space.
- Disk model, firmware revision, and WMI status.

It writes to `$env:USERPROFILE\Desktop\DiskHealthReport.txt`. That directory must exist; redirected or OneDrive-managed desktops may use a different location. Each run replaces the previous report, so save a copy if you want to compare results over time.

If local execution policy blocks the script, review it and follow your organization's approved PowerShell execution policy. The script is intended for Windows; installing PowerShell on Linux does not provide the Windows storage APIs it needs.

## 🩺 Coach’s notes

- **A clean scoreboard is not a guarantee.** SMART can flag risk, but cannot predict every disk failure. Keep backups.
- **Memory usage is not memory health.** Use a dedicated boot-time memory test when investigating RAM faults.
- **Know your playing field.** Containers, virtual machines, unsupported hardware, and restricted permissions can hide sensors, disks, firmware, or kernel logs.
- **Read the report, not just the exit code.** The Linux script continues past many unavailable commands and diagnostic errors.
- **Protect your stats.** Reports may contain hostnames, disk serial numbers, hardware details, and system logs. Review them before sharing.

## 🛠️ Training ground for contributors

Check Bash syntax before running the Linux report:

```bash
bash -n ubuntu_health_report.sh
```

Then run the script and inspect the generated report for all 15 sections and `REPORT COMPLETE`. There is no automated test suite in this repository. Validate Windows changes on a Windows machine with the required Storage and CIM commands.

The Linux report has been smoke-tested in a Debian cloud container. Physical hardware diagnostics and the Windows script require validation on their target systems.

---

**Keep your system match-ready. Back up, check in, and play the long game. 🏅**
