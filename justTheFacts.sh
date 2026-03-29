#!/usr/bin/env bash
# ─────────────────────────────────────────────
#  justTheFacts.sh — fast, colorful system info
# ─────────────────────────────────────────────

# ── Colors ────────────────────────────────────
RESET='\033[0m'
SEP='\033[38;5;238m'       # dark grey  — borders
LABEL='\033[38;5;81m'      # cyan-blue  — left column
VAL='\033[38;5;255m'       # bright white — values
HEAD='\033[1;38;5;214m'    # bold orange — header
DIM='\033[38;5;245m'       # muted grey  — secondary values
ACCENT='\033[38;5;149m'    # soft green  — highlights

# ── Table geometry ────────────────────────────
LW=22   # label column width
VW=46   # value column width
TW=$(( LW + VW + 7 ))  # total width (borders + padding)

# ── Drawing helpers ───────────────────────────
hline_top()    { printf "${SEP}┌$(printf '─%.0s' $(seq 1 $(( LW+2 ))))┬$(printf '─%.0s' $(seq 1 $(( VW+2 ))))┐${RESET}\n"; }
hline_mid()    { printf "${SEP}├$(printf '─%.0s' $(seq 1 $(( LW+2 ))))┼$(printf '─%.0s' $(seq 1 $(( VW+2 ))))┤${RESET}\n"; }
hline_sep()    { printf "${SEP}╞$(printf '═%.0s' $(seq 1 $(( LW+2 ))))╪$(printf '═%.0s' $(seq 1 $(( VW+2 ))))╡${RESET}\n"; }
hline_bot()    { printf "${SEP}└$(printf '─%.0s' $(seq 1 $(( LW+2 ))))┴$(printf '─%.0s' $(seq 1 $(( VW+2 ))))┘${RESET}\n"; }

row() {
  local label="$1" value="$2"
  printf "${SEP}│ ${LABEL}%-${LW}s${SEP} │ ${VAL}%-${VW}s${SEP} │${RESET}\n" "$label" "$value"
}

header_row() {
  local text="$1"
  local pad=$(( (LW + VW + 3 - ${#text}) / 2 ))
  printf "${SEP}│${HEAD}%*s%s%*s${SEP}│${RESET}\n" $pad "" "$text" $(( LW + VW + 3 - pad - ${#text} )) ""
}

blank_row() {
  printf "${SEP}│ %-$(( LW+2 ))s│ %-$(( VW+2 ))s│${RESET}\n" "" ""
}

# ── Parallel data gathering ────────────────────
# Each fact is collected in a background job writing to a temp file.
# We wait for all jobs, then render — total time = slowest single fact.

TMPDIR_JTF=$(mktemp -d)
trap 'rm -rf "$TMPDIR_JTF"' EXIT

gather() { local key="$1"; shift; ("$@" 2>/dev/null) > "$TMPDIR_JTF/$key" & }
get()     { cat "$TMPDIR_JTF/$1" 2>/dev/null || echo "n/a"; }

# ── Detect OS for branching ───────────────────
OS_TYPE=$(uname -s)

# ── Spawn background jobs ─────────────────────
gather hostname         hostname -s
gather fqdn             hostname -f
gather arch             uname -m
gather kernel           uname -r
gather kernel_full      uname -v
gather cpu_cores        bash -c 'nproc 2>/dev/null || sysctl -n hw.logicalcpu'
gather uptime           bash -c 'uptime | sed "s/.*up //" | sed "s/, *[0-9]* users\{0,1\}.*//"'
gather load             bash -c 'uptime | grep -oE "load averages?: [0-9.]+ [0-9.]+ [0-9.]+" | grep -oE "[0-9.]+ [0-9.]+ [0-9.]+"'
gather shell            bash -c 'basename "$SHELL"'
gather user             id -un

if [[ "$OS_TYPE" == "Darwin" ]]; then
  gather os_name        bash -c 'sw_vers -productName'
  gather os_ver         bash -c 'sw_vers -productVersion'
  gather os_build       bash -c 'sw_vers -buildVersion'
  gather cpu_model      bash -c 'sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model'
  gather ram_total      bash -c 'sysctl -n hw.memsize | awk "{printf \"%.0f GiB\", \$1/1073741824}"'
  gather ram_used       bash -c '
    vm_stat | awk "
      /Pages active/    { active=\$3 }
      /Pages wired/     { wired=\$4 }
      /Pages compressed/{ comp=\$3 }
      END { printf \"%.1f GiB used\", (active+wired+comp)*4096/1073741824 }
    "
  '
  gather disk           bash -c 'df -h / | awk "NR==2 {print \$3\" used / \"\$2\" total (\"\$5\" full)\"}"'
  gather gpu            bash -c 'system_profiler SPDisplaysDataType 2>/dev/null | awk -F": " "/Chipset Model/{print \$2; exit}"'
  gather serial         bash -c 'system_profiler SPHardwareDataType 2>/dev/null | awk -F": " "/Serial Number/{print \$2}"'
  gather model          bash -c 'system_profiler SPHardwareDataType 2>/dev/null | awk -F": " "/Model Name/{print \$2; exit}"'
else
  gather os_name        bash -c 'grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather os_ver         bash -c 'grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather os_build       bash -c 'grep "^BUILD_ID=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather cpu_model      bash -c 'grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed "s/^ //"'
  gather ram_total      bash -c 'free -h | awk "/^Mem/{print \$2\" total\"}"'
  gather ram_used       bash -c 'free -h | awk "/^Mem/{print \$3\" used\"}"'
  gather disk           bash -c 'df -h / | awk "NR==2 {print \$3\" used / \"\$2\" total (\"\$5\" full)\"}"'
  gather gpu            bash -c 'lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | sed "s/.*: //"'
  gather serial         bash -c 'cat /sys/class/dmi/id/product_serial 2>/dev/null'
  gather model          bash -c 'cat /sys/class/dmi/id/product_name 2>/dev/null'
fi

# Wait for all background jobs
wait

# ── Render table ──────────────────────────────
clear
echo
printf "  ${ACCENT}justTheFacts.sh${DIM} — system snapshot @ $(date '+%Y-%m-%d %H:%M:%S')${RESET}\n\n"

hline_top
header_row " System "
hline_sep
row "Hostname"       "$(get hostname)"
row "FQDN"           "$(get fqdn)"
row "Model"          "$(get model)"
row "Serial"         "$(get serial)"
hline_mid
header_row " OS & Kernel "
hline_sep
row "OS"             "$(get os_name) $(get os_ver)"
[[ -n "$(get os_build)" && "$(get os_build)" != "n/a" ]] && row "Build" "$(get os_build)"
row "Kernel"         "$(get kernel)"
row "Architecture"   "$(get arch)"
hline_mid
header_row " Hardware "
hline_sep
row "CPU"            "$(get cpu_model)"
row "CPU Cores"      "$(get cpu_cores) logical"
row "GPU"            "$(get gpu)"
row "Memory"         "$(get ram_total)  /  $(get ram_used)"
row "Disk (/)"       "$(get disk)"
hline_mid
header_row " Runtime "
hline_sep
row "User"           "$(get user)"
row "Shell"          "$(get shell)"
row "Uptime"         "$(get uptime)"
row "Load Average"   "$(get load)"
hline_bot
echo
