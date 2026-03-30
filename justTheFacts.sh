#!/usr/bin/env bash
# ─────────────────────────────────────────────
#  justTheFacts.sh — fast, colorful system info
# ─────────────────────────────────────────────

# ── Colors ────────────────────────────────────
RESET='\033[0m'
SEP='\033[38;5;238m'       # dark grey  — borders
LABEL='\033[1;38;5;81m'    # bold cyan-blue — left column
VAL='\033[38;5;255m'       # bright white — values
HEAD='\033[1;38;5;214m'    # bold orange — header
DIM='\033[38;5;245m'       # muted grey  — secondary values
ACCENT='\033[38;5;149m'    # soft green  — highlights
OK='\033[38;5;149m'        # green — check pass
FAIL='\033[38;5;203m'      # coral — check fail

# ── Table geometry ────────────────────────────
LW=22   # label column width
VW=46   # value column width
IW=$(( LW + VW + 5 ))  # inner width (cols + padding + 1 divider)

# ── Drawing helpers ───────────────────────────
# Full-width lines (no internal divider) — used around headers
hline_top()   { printf "${SEP}┌$(printf '─%.0s' $(seq 1 $IW))┐${RESET}\n"; }
hline_bot()   { printf "${SEP}└$(printf '─%.0s' $(seq 1 $IW))┘${RESET}\n"; }
# Closes column divider, full-width — used between sections
hline_close() { printf "${SEP}├$(printf '─%.0s' $(seq 1 $(( LW+2 ))))┴$(printf '─%.0s' $(seq 1 $(( VW+2 ))))┤${RESET}\n"; }
# Opens column divider — used after each header
hline_open()  { printf "${SEP}╞$(printf '═%.0s' $(seq 1 $(( LW+2 ))))╤$(printf '═%.0s' $(seq 1 $(( VW+2 ))))╡${RESET}\n"; }

row() {
  local label="$1" value="$2"
  if [[ ${#value} -gt $VW ]]; then
    value="${value:0:$(( VW - 1 ))}…"
  fi
  printf "${SEP}│ ${LABEL}%-${LW}s${RESET}${SEP} │ ${VAL}%-${VW}s${SEP} │${RESET}\n" "$label" "$value"
}

# check_row: shows ✓ (green) or ✗ (coral) followed by detail text.
# Pads manually to avoid printf mis-counting multi-byte UTF-8 icon chars.
check_row() {
  local label="$1" ok="$2" detail="$3"
  local max=$(( VW - 2 ))   # VW minus icon(1) + space(1)
  if [[ ${#detail} -gt $max ]]; then
    detail="${detail:0:$(( max - 1 ))}…"
  fi
  local padding
  printf -v padding '%*s' $(( max - ${#detail} )) ''
  local icon icon_color
  if [[ "$ok" == "1" ]]; then
    icon="✓"; icon_color="$OK"
  else
    icon="✗"; icon_color="$FAIL"
  fi
  printf "${SEP}│ ${LABEL}%-${LW}s${RESET}${SEP} │ ${icon_color}${icon} ${VAL}${detail}${padding}${SEP} │${RESET}\n" "$label"
}

header_row() {
  local text="$1"
  local pad=$(( (IW - ${#text}) / 2 ))
  printf "${SEP}│${HEAD}%*s%s%*s${SEP}│${RESET}\n" $pad "" "$text" $(( IW - pad - ${#text} )) ""
}

# ── Parallel data gathering ────────────────────
# Each fact is collected in a background job writing to a temp file.
# We wait for all jobs, then render — total time = slowest single fact.

TMPDIR_JTF=$(mktemp -d)
trap 'rm -rf "$TMPDIR_JTF"' EXIT

gather() { local key="$1"; shift; ("$@" 2>/dev/null) > "$TMPDIR_JTF/$key" & }
get()     { cat "$TMPDIR_JTF/$1" 2>/dev/null || echo "n/a"; }

# For build checks: writes "1|detail" (ok) or "0|detail" (fail)
get_ok()     { cut -d'|' -f1  < "$TMPDIR_JTF/$1" 2>/dev/null || echo "0"; }
get_detail() { cut -d'|' -f2- < "$TMPDIR_JTF/$1" 2>/dev/null || echo "n/a"; }

# ── Detect OS for branching ───────────────────
OS_TYPE=$(uname -s)

# On NetBSD, /sbin and /usr/sbin are not always in the PATH of non-interactive
# shells. Sysctl, ifconfig, etc. live there — prepend them so subshells find them.
[[ "$OS_TYPE" == "NetBSD" ]] && export PATH="/sbin:/usr/sbin:$PATH"

# ── Spawn background jobs ─────────────────────
gather hostname         hostname -s
gather fqdn             bash -c '
  fqdn=$(hostname -f 2>/dev/null)
  if [[ -n "$fqdn" ]]; then echo "$fqdn"; exit; fi
  hn=$(hostname 2>/dev/null)
  # NetBSD/BSD: try kern.domainname sysctl or domainname command
  dn=$(sysctl -n kern.domainname 2>/dev/null || domainname 2>/dev/null)
  if [[ -n "$dn" && "$dn" != "(none)" && "$dn" != "localdomain" ]]; then
    echo "${hn}.${dn}"; exit
  fi
  # Parse /etc/hosts for a dotted name matching our hostname
  match=$(awk -v h="$hn" "!/^[[:space:]]*#/ && /\./ { for(i=2;i<=NF;i++) if(\$i==h){print \$2;exit} }" /etc/hosts 2>/dev/null)
  [[ -n "$match" ]] && echo "$match" && exit
  echo "$hn"
'
gather ip               bash -c '
  v=$(ipconfig getifaddr en0 2>/dev/null)
  [[ -n "$v" ]] && echo "$v" && exit
  v=$(ip route get 1 2>/dev/null | awk "/src /{for(i=1;i<=NF;i++) if(\$i==\"src\"){print \$(i+1);exit}}")
  [[ -n "$v" ]] && echo "$v" && exit
  for ifc in /sbin/ifconfig /usr/sbin/ifconfig ifconfig; do
    [[ "$ifc" == ifconfig ]] || [[ -x "$ifc" ]] || continue
    v=$("$ifc" 2>/dev/null | awk "/inet / && !/127\.0\.0\.1/{print \$2; exit}")
    [[ -n "$v" ]] && echo "$v" && exit
  done
'
gather arch             uname -m
gather kernel           uname -r
# cpu_cores is gathered per-OS below for richer platform-specific detail
gather uptime           bash -c 'uptime | sed "s/.*up //" | sed "s/, *[0-9]* users\{0,1\}.*//"'
gather load             bash -c 'uptime | awk -F"load averages?:" "{print \$2}" | awk "{print \$1, \$2, \$3}"'
gather shell            bash -c 'basename "$SHELL"'
gather user             id -un
gather clang            bash -c '
  command -v clang >/dev/null 2>&1 || which clang >/dev/null 2>&1 || { echo "not installed"; exit; }
  clang --version 2>&1 | head -1
'
gather gcc              bash -c '
  real_gcc=$(ls /usr/local/bin/gcc-* /opt/homebrew/bin/gcc-* 2>/dev/null | sort -V | tail -1)
  if [[ -n "$real_gcc" ]]; then
    "$real_gcc" --version 2>/dev/null | head -1
  else
    ver=$(gcc --version 2>/dev/null | head -1)
    if echo "$ver" | grep -qi clang; then
      echo "not installed (gcc is aliased to clang)"
    else
      echo "$ver"
    fi
  fi
'

# ── Build environment checks (write "1|detail" or "0|detail") ──
_chk() {
  local cmd="$1" label="$2" ver_args="${3:---version}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v; v=$("$cmd" $ver_args 2>/dev/null | head -1)
    echo "1|${v:-$label installed}"
  else
    echo "0|not found"
  fi
}
gather chk_make      bash -c '
  if command -v gmake >/dev/null 2>&1; then
    v=$(gmake --version 2>/dev/null | grep -v "^[[:space:]]*$" | head -1)
    echo "1|$v"; exit
  fi
  if command -v make >/dev/null 2>&1; then
    v=$(cd /tmp && make --version 2>/dev/null | grep -v "^[[:space:]]*$" | head -1)
    [[ -z "$v" ]] && v=$(cd /tmp && make -V .MAKE.VERSION 2>/dev/null | grep -v "^[[:space:]]*$" | head -1 | awk "{print \"BSD make \" \$1}")
    [[ -z "$v" ]] && v="BSD make (system)"
    echo "1|$v"; exit
  fi
  echo "0|not found"
'
gather chk_cmake     bash -c 'command -v cmake >/dev/null 2>&1 && v=$(cmake --version 2>/dev/null | head -1) && echo "1|$v" || echo "0|not found"'
gather chk_ninja     bash -c 'command -v ninja >/dev/null 2>&1 && v=$(ninja --version 2>/dev/null) && echo "1|ninja $v" || echo "0|not found"'
gather chk_pkgconf   bash -c 'command -v pkg-config >/dev/null 2>&1 && v=$(pkg-config --version 2>/dev/null) && echo "1|pkg-config $v" || echo "0|not found"'
gather chk_autoconf  bash -c 'command -v autoconf >/dev/null 2>&1 && v=$(autoconf --version 2>/dev/null | head -1) && echo "1|$v" || echo "0|not found"'
gather chk_automake  bash -c 'command -v automake >/dev/null 2>&1 && v=$(automake --version 2>/dev/null | head -1) && echo "1|$v" || echo "0|not found"'
gather chk_libtool   bash -c '
  # Locate a binary by name: tries PATH, type -P, known dirs, then find
  _find_bin() {
    local name="$1" p found
    found=$(command -v "$name" 2>/dev/null)
    [[ -n "$found" ]] && echo "$found" && return 0
    found=$(type -P "$name" 2>/dev/null)
    [[ -n "$found" ]] && echo "$found" && return 0
    # Walk every directory in the current PATH explicitly
    IFS=: read -ra _dirs <<< "$PATH"
    for p in "${_dirs[@]}"; do
      [[ -x "$p/$name" ]] && echo "$p/$name" && return 0
    done
    # Check common locations that may not be in non-interactive PATH
    for p in /usr/bin /usr/local/bin /bin /usr/sbin /usr/local/sbin /sbin \
              /opt/homebrew/bin /home/linuxbrew/.linuxbrew/bin \
              /opt/local/bin /usr/pkg/bin; do
      [[ -x "$p/$name" ]] && echo "$p/$name" && return 0
    done
    # Last resort: find the binary under /usr and /opt
    found=$(find /usr /opt -maxdepth 5 -name "$name" -type f -perm /111 2>/dev/null | head -1)
    [[ -n "$found" ]] && echo "$found" && return 0
    return 1
  }
  for name in libtool glibtool; do
    bin=$(_find_bin "$name") || continue
    v=$("$bin" --version 2>/dev/null | head -1)
    [[ -z "$v" ]] && v=$("$bin" -V 2>&1 | head -1)
    echo "1|${v:-$name installed}"
    exit
  done
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo "0|not found (package: libtool-bin)"
  else
    echo "0|not found"
  fi
'
gather chk_git       bash -c 'command -v git >/dev/null 2>&1 && v=$(git --version 2>/dev/null) && echo "1|$v" || echo "0|not found"'
gather chk_openssl   bash -c 'command -v openssl >/dev/null 2>&1 && v=$(openssl version 2>/dev/null) && echo "1|$v" || echo "0|not found"'
gather chk_node      bash -c 'command -v node >/dev/null 2>&1 && v=$(node --version 2>/dev/null) && echo "1|node $v" || echo "0|not found"'
gather chk_npm       bash -c 'command -v npm >/dev/null 2>&1 && v=$(npm --version 2>/dev/null) && echo "1|npm $v" || echo "0|not found"'

if [[ "$OS_TYPE" == "Darwin" ]]; then
  gather os_name      bash -c 'sw_vers -productName'
  gather os_ver       bash -c 'sw_vers -productVersion'
  gather os_build     bash -c 'sw_vers -buildVersion'
  gather cpu_model    bash -c 'sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model'
  gather cpu_cores    bash -c '
    logical=$(sysctl -n hw.logicalcpu 2>/dev/null)
    physical=$(sysctl -n hw.physicalcpu 2>/dev/null)
    pcores=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)
    ecores=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)
    if [[ -n "$pcores" && -n "$ecores" ]]; then
      echo "${pcores}P + ${ecores}E (${logical} logical)"
    elif [[ -n "$physical" && -n "$logical" && "$physical" != "$logical" ]]; then
      echo "${physical} physical, ${logical} logical"
    else
      echo "${logical:-$physical} logical"
    fi
  '
  gather cpu_freq     bash -c '
    freq=$(sysctl -n hw.cpufrequency_max 2>/dev/null)
    [[ -z "$freq" ]] && freq=$(sysctl -n hw.cpufrequency 2>/dev/null)
    if [[ -n "$freq" && "$freq" -gt 0 ]] 2>/dev/null; then
      awk -v f="$freq" "BEGIN{printf \"%.2f GHz\", f/1e9}"; exit
    fi
    sp=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F": " "/Processor Speed/{print \$2; exit}")
    [[ -n "$sp" ]] && echo "$sp" && exit
    echo "variable (Apple Silicon)"
  '
  gather ram_total    bash -c 'sysctl -n hw.memsize | awk "{printf \"%.0f GB\", \$1/1000000000}"'
  gather ram_used     bash -c '
    vm_stat | awk "
      /Pages active/    { active=\$3 }
      /Pages wired/     { wired=\$4 }
      /Pages compressed/{ comp=\$3 }
      END { printf \"%.1f GB used\", (active+wired+comp)*4096/1000000000 }
    "
  '
  gather ram_pct      bash -c '
    total=$(sysctl -n hw.memsize 2>/dev/null)
    vm_stat | awk -v tot="$total" "
      /Pages active/    { active=\$3 }
      /Pages wired/     { wired=\$4 }
      /Pages compressed/{ comp=\$3 }
      END { used=(active+wired+comp)*4096; printf \"%d%% free\", (1-(used/tot))*100 }
    "
  '
  gather swap         bash -c '
    sysctl vm.swapusage 2>/dev/null | awk "/swapusage/{
      for(i=1;i<=NF;i++){
        if(\$i==\"total\"){t=\$(i+2); gsub(/[^0-9.]/,\"\",t)}
        if(\$i==\"used\") {u=\$(i+2); gsub(/[^0-9.]/,\"\",u)}
      }
      if(t+0>0) printf \"%.1f GB used / %.1f GB total (%d%% free)\", u/1024, t/1024, (t-u)/t*100
      else print \"none configured\"
    }"
  '
  gather disk         bash -c 'df -Pk / | awk "NR==2 {printf \"%.1f GB used / %.0f GB total (%d%% free)\", \$3*1024/1e9, \$2*1024/1e9, 100-int(\$5)}"'
  gather gpu          bash -c '
    info=$(system_profiler SPDisplaysDataType 2>/dev/null)
    model=$(echo "$info" | awk -F": " "/Chipset Model/{print \$2; exit}")
    cores=$(echo "$info" | awk -F": " "/Total Number of Cores/{print \$2; exit}")
    vram=$(echo "$info"  | awk -F": " "/VRAM \\(Total\\)/{print \$2; exit}")
    [[ -z "$vram" ]] && vram=$(echo "$info" | awk -F": " "/VRAM \\(Dynamic, Max\\)/{print \$2; exit}")
    result="$model"
    [[ -n "$cores" ]] && result="$result, $cores cores"
    [[ -n "$vram"  ]] && result="$result, $vram VRAM"
    echo "$result"
  '
  gather serial       bash -c 'system_profiler SPHardwareDataType 2>/dev/null | awk -F": " "/Serial Number/{print \$2}"'
  gather model        bash -c 'system_profiler SPHardwareDataType 2>/dev/null | awk -F": " "/Model Name/{print \$2; exit}"'
  gather chk_xclt     bash -c '
    path=$(xcode-select -p 2>/dev/null)
    [[ -n "$path" && -d "$path" ]] && echo "1|$path" || echo "0|run: xcode-select --install"
  '

elif [[ "$OS_TYPE" == "NetBSD" ]]; then
  gather os_name      bash -c 'uname -s'
  gather os_ver       bash -c 'uname -r'
  gather os_build     bash -c 'uname -v | awk -F"[()]" "{print \$2}"'
  gather cpu_model    bash -c '
    cd /tmp
    m=$(sysctl -n hw.model 2>/dev/null)
    [[ -z "$m" ]] && m=$(sysctl -n machdep.cpu_brand 2>/dev/null)
    [[ -z "$m" ]] && m=$(sysctl -n machdep.dmi.processor-version 2>/dev/null)
    [[ -z "$m" ]] && m=$(uname -p 2>/dev/null)
    echo "$m"
  '
  gather cpu_cores    bash -c '
    cd /tmp
    logical=$(sysctl -n hw.ncpuonline 2>/dev/null)
    [[ -z "$logical" ]] && logical=$(sysctl -n hw.ncpu 2>/dev/null)
    [[ -z "$logical" ]] && logical=$(sysctl hw.ncpu 2>/dev/null | awk "{print \$NF}")
    # Try Intel SMT topology keys
    physical=$(sysctl -n machdep.cpu.core_count 2>/dev/null)
    threads=$(sysctl -n machdep.cpu.thread_count 2>/dev/null)
    if [[ -n "$physical" && -n "$threads" && "$threads" -gt "$physical" ]] 2>/dev/null; then
      echo "${physical} cores, ${logical} threads (HT)"
    elif [[ -n "$physical" && -n "$logical" && "$physical" != "$logical" ]] 2>/dev/null; then
      echo "${physical} cores (${logical} logical)"
    else
      echo "${logical} logical"
    fi
  '
  gather ram_total    bash -c '
    cd /tmp
    total=$(sysctl -n hw.physmem64 2>/dev/null)
    [[ -z "$total" ]] && total=$(sysctl hw.physmem64 2>/dev/null | awk "{print \$NF}")
    [[ -z "$total" || "$total" -le 0 ]] 2>/dev/null && total=$(sysctl -n hw.physmem 2>/dev/null)
    [[ -z "$total" ]] && total=$(sysctl hw.physmem 2>/dev/null | awk "{print \$NF}")
    if [[ -z "$total" || "$total" -le 0 ]] 2>/dev/null; then
      npages=$(sysctl -n vm.uvmexp.npages 2>/dev/null)
      [[ -z "$npages" ]] && npages=$(sysctl vm.uvmexp.npages 2>/dev/null | awk "{print \$NF}")
      psize=$(sysctl -n hw.pagesize 2>/dev/null)
      [[ -z "$psize" ]] && psize=$(sysctl hw.pagesize 2>/dev/null | awk "{print \$NF}")
      [[ -z "$psize" || "$psize" -le 0 ]] 2>/dev/null && psize=4096
      [[ -n "$npages" && "$npages" -gt 0 ]] 2>/dev/null && total=$(( npages * psize ))
    fi
    [[ -n "$total" && "$total" -gt 0 ]] 2>/dev/null && \
      awk -v t="$total" "BEGIN{printf \"%.0f GB\", t/1000000000}"
  '
  gather ram_used     bash -c '
    cd /tmp
    npages=$(sysctl -n vm.uvmexp.npages 2>/dev/null)
    [[ -z "$npages" ]] && npages=$(sysctl vm.uvmexp.npages 2>/dev/null | awk "{print \$NF}")
    free_p=$(sysctl -n vm.uvmexp.free 2>/dev/null)
    [[ -z "$free_p" ]] && free_p=$(sysctl vm.uvmexp.free 2>/dev/null | awk "{print \$NF}")
    psize=$(sysctl -n hw.pagesize 2>/dev/null)
    [[ -z "$psize" ]] && psize=$(sysctl hw.pagesize 2>/dev/null | awk "{print \$NF}")
    [[ -z "$psize" || "$psize" -le 0 ]] 2>/dev/null && psize=4096
    if [[ -n "$npages" && -n "$free_p" && "$npages" -gt 0 ]] 2>/dev/null; then
      awk -v np="$npages" -v fp="$free_p" -v ps="$psize" \
        "BEGIN{used=(np-fp)*ps; if(used<0)used=0; printf \"%.1f GB used\", used/1000000000}"
    fi
  '
  gather ram_pct      bash -c '
    cd /tmp
    npages=$(sysctl -n vm.uvmexp.npages 2>/dev/null)
    [[ -z "$npages" ]] && npages=$(sysctl vm.uvmexp.npages 2>/dev/null | awk "{print \$NF}")
    free_p=$(sysctl -n vm.uvmexp.free 2>/dev/null)
    [[ -z "$free_p" ]] && free_p=$(sysctl vm.uvmexp.free 2>/dev/null | awk "{print \$NF}")
    if [[ -n "$npages" && -n "$free_p" && "$npages" -gt 0 ]] 2>/dev/null; then
      awk -v np="$npages" -v fp="$free_p" "BEGIN{printf \"%d%% free\", (fp/np)*100}"
    fi
  '
  gather swap         bash -c '
    cd /tmp
    out=$(swapctl -s 2>/dev/null)
    if [[ -z "$out" ]]; then echo "none configured"; exit; fi
    echo "$out" | awk "{
      for(i=1;i<=NF;i++){
        if(\$i==\"available:\") total=\$(i+1)+0
        if(\$i==\"used:\")      used=\$(i+1)+0
      }
      if(total+0>0) printf \"%.1f GB used / %.1f GB total (%d%% free)\", used/1e6, total/1e6, (total-used)/total*100
      else print \"none configured\"
    }"
  '
  gather disk         bash -c 'df -Pk / | awk "NR==2 {printf \"%.1f GB used / %.0f GB total (%d%% free)\", \$3*1024/1e9, \$2*1024/1e9, 100-int(\$5)}"'
  gather gpu          bash -c '
    _gpu_pat="^(vga|radeon|nouveau|gffb|genfb|uvesafb|wsdisplay|vesabios|bochs|cirrus|vmware|vmt)[0-9]* at "
    for f in /var/run/dmesg.boot /var/log/dmesg; do
      [[ -r "$f" ]] || continue
      line=$(grep -E "$_gpu_pat" "$f" 2>/dev/null | head -1)
      if [[ -n "$line" ]]; then
        desc=$(echo "$line" | sed "s/.*: //")
        [[ -n "$desc" ]] && echo "$desc" && exit
        echo "$line" | awk "{print \$1}" && exit
      fi
    done
    # Try live dmesg
    line=$(dmesg 2>/dev/null | grep -E "$_gpu_pat" | head -1)
    if [[ -n "$line" ]]; then
      desc=$(echo "$line" | sed "s/.*: //")
      [[ -n "$desc" ]] && echo "$desc" && exit
    fi
    # Try pcictl across common bus names
    for bus in pci0 pci1 pci2; do
      line=$(pcictl "$bus" list 2>/dev/null | grep -i "display\|vga" | head -1 | sed "s/^[^:]*: //")
      [[ -n "$line" ]] && echo "$line" && exit
    done
  '
  gather serial       bash -c 'sysctl -n machdep.dmi.system-serial-number 2>/dev/null'
  gather model        bash -c 'sysctl -n machdep.dmi.system-product-name 2>/dev/null'
  gather chk_xclt     bash -c 'echo "0|n/a (macOS only)"'

else
  # Linux
  gather os_name      bash -c 'grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather os_ver       bash -c 'grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather os_build     bash -c 'grep "^BUILD_ID=" /etc/os-release | cut -d= -f2 | tr -d "\""'
  gather cpu_model    bash -c '
    m=$(grep "^model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed "s/^ //")
    [[ -z "$m" ]] && m=$(lscpu 2>/dev/null | awk -F":[[:space:]]+" "/^Model name/{print \$2; exit}")
    [[ -z "$m" ]] && m=$(cat /proc/device-tree/model 2>/dev/null | tr -d "\0")
    [[ -z "$m" ]] && m=$(grep "^Hardware" /proc/cpuinfo | head -1 | cut -d: -f2 | sed "s/^ //")
    echo "$m"
  '
  gather cpu_cores    bash -c '
    physical=$(grep "^cpu cores" /proc/cpuinfo | head -1 | awk -F": " "{print \$2}")
    logical=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
    if [[ -n "$physical" && "$physical" != "$logical" ]]; then
      echo "${physical} physical, ${logical} logical"
    else
      echo "${logical} logical"
    fi
  '
  gather ram_total    bash -c 'free -b | awk "/^Mem/{printf \"%.0f GB\", \$2/1000000000}"'
  gather ram_used     bash -c 'free -b | awk "/^Mem/{printf \"%.1f GB used\", \$3/1000000000}"'
  gather ram_pct      bash -c 'free -b | awk "/^Mem/{printf \"%d%% free\", ((\$2-\$3)/\$2)*100}"'
  gather swap         bash -c '
    free -b 2>/dev/null | awk "/^Swap/{
      if(\$2+0>0) printf \"%.1f GB used / %.1f GB total (%d%% free)\", \$3/1e9, \$2/1e9, (\$2-\$3)/\$2*100
      else print \"none configured\"
    }"
  '
  gather disk         bash -c 'df -Pk / | awk "NR==2 {printf \"%.1f GB used / %.0f GB total (%d%% free)\", \$3*1024/1e9, \$2*1024/1e9, 100-int(\$5)}"'
  gather gpu          bash -c '
    v=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | sed "s/.*: //")
    [[ -n "$v" ]] && echo "$v" && exit
    # Raspberry Pi: identify VideoCore generation from device tree model
    dtmodel=$(cat /proc/device-tree/model 2>/dev/null | tr -d "\0")
    if echo "$dtmodel" | grep -qi "raspberry\|bcm2"; then
      case "$dtmodel" in
        *"Pi 5"*)                    echo "VideoCore VII ($dtmodel)"  ;;
        *"Pi 4"*|*"Compute Module 4"*) echo "VideoCore VI ($dtmodel)" ;;
        *"Pi 3"*|*"Pi Zero 2"*)      echo "VideoCore IV ($dtmodel)"  ;;
        *)                           echo "VideoCore ($dtmodel)"      ;;
      esac
      exit
    fi
    # Generic ARM: check DRM subsystem
    for d in /sys/class/drm/card[0-9]*/device; do
      name=$(cat "$d/product_name" 2>/dev/null)
      [[ -n "$name" ]] && echo "$name" && exit
    done
    compat=$(cat /sys/firmware/devicetree/base/gpu/compatible 2>/dev/null | tr -d "\0")
    [[ -n "$compat" ]] && echo "$compat"
  '
  gather serial       bash -c 'cat /sys/class/dmi/id/product_serial 2>/dev/null'
  gather model        bash -c 'cat /sys/class/dmi/id/product_name 2>/dev/null'
  gather chk_xclt     bash -c 'echo "0|n/a (macOS only)"'
fi

# Wait for all background jobs
wait

# ── Render table ──────────────────────────────
clear
echo
printf "  ${ACCENT}justTheFacts.sh${DIM} — system snapshot @ $(date '+%Y-%m-%d %H:%M:%S')${RESET}\n\n"

hline_top
header_row " System "
hline_open
row "Hostname"         "$(get hostname)"
row "IP Address"       "$(get ip)"
row "FQDN"             "$(get fqdn)"
_model=$(get model);  [[ -n "$_model"  && "$_model"  != "n/a" ]] && row "Model"  "$_model"
_serial=$(get serial); [[ -n "$_serial" && "$_serial" != "n/a" ]] && row "Serial" "$_serial"
hline_close
header_row " OS & Kernel "
hline_open
row "OS"               "$(get os_name) $(get os_ver)"
[[ -n "$(get os_build)" && "$(get os_build)" != "n/a" ]] && row "Build" "$(get os_build)"
row "Kernel"           "$(get kernel)"
row "Architecture"     "$(get arch)"
hline_close
header_row " Hardware "
hline_open
row "CPU"              "$(get cpu_model)"
row "CPU Cores"        "$(get cpu_cores)"
[[ "$OS_TYPE" == "Darwin" ]] && row "CPU Freq" "$(get cpu_freq)"
row "GPU"              "$(get gpu)"
row "Memory"           "$(get ram_used)  /  $(get ram_total)  ($(get ram_pct))"
row "Swap"             "$(get swap)"
row "Disk (/)"         "$(get disk)"
hline_close
header_row " Compilers "
hline_open
row "clang"            "$(get clang)"
row "gcc"              "$(get gcc)"
hline_close
header_row " Build Environment "
hline_open
check_row "make"       "$(get_ok chk_make)"     "$(get_detail chk_make)"
check_row "cmake"      "$(get_ok chk_cmake)"    "$(get_detail chk_cmake)"
check_row "ninja"      "$(get_ok chk_ninja)"    "$(get_detail chk_ninja)"
check_row "pkg-config" "$(get_ok chk_pkgconf)"  "$(get_detail chk_pkgconf)"
check_row "autoconf"   "$(get_ok chk_autoconf)" "$(get_detail chk_autoconf)"
check_row "automake"   "$(get_ok chk_automake)" "$(get_detail chk_automake)"
check_row "libtool"    "$(get_ok chk_libtool)"  "$(get_detail chk_libtool)"
check_row "git"        "$(get_ok chk_git)"      "$(get_detail chk_git)"
check_row "openssl"    "$(get_ok chk_openssl)"  "$(get_detail chk_openssl)"
check_row "node"       "$(get_ok chk_node)"     "$(get_detail chk_node)"
check_row "npm"        "$(get_ok chk_npm)"      "$(get_detail chk_npm)"
[[ "$OS_TYPE" == "Darwin" ]] && \
check_row "Xcode CLT"  "$(get_ok chk_xclt)"     "$(get_detail chk_xclt)"
hline_close
header_row " Runtime "
hline_open
row "User"             "$(get user)"
row "Shell"            "$(get shell)"
row "Uptime"           "$(get uptime)"
row "Load Average"     "$(get load)"
hline_bot
echo
