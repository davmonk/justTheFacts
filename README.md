# justTheFacts.sh

A fast, colorful system information script that displays a structured table of facts about the machine it runs on.

## What it does

Displays a formatted table covering:

| Section | Fields |
|---|---|
| **System** | Hostname, IP address, FQDN, Model, Serial number |
| **OS & Kernel** | OS name/version, build ID, kernel version, architecture |
| **Hardware** | CPU model, core count, GPU, memory usage, swap usage, disk usage |
| **Compilers** | clang version, gcc version |
| **Build Environment** | make, cmake, ninja, pkg-config, autoconf, automake, libtool, git, openssl, node, npm — each with ✓/✗ and version |
| **Runtime** | Current user, shell, uptime, load average |

On macOS the Hardware section also shows CPU frequency and Xcode Command Line Tools status.

## How it works

All data is gathered in parallel: each fact is collected as a background job writing to a temporary file, then `wait` synchronises them all before the table is rendered. Total runtime is bounded by the slowest single fact rather than the sum of all facts — typically under one second.

```
gather hostname  hostname -s        # spawns background job → writes to /tmp/jtf.XXXX/hostname
gather ip        bash -c '...'      # spawns background job → writes to /tmp/jtf.XXXX/ip
...
wait                                # wait for all jobs
row "Hostname" "$(get hostname)"    # render from temp files
```

The table uses Unicode box-drawing characters and 256-colour ANSI escape codes. Multi-byte UTF-8 characters (✓/✗) are padded manually since `printf "%-Ns"` counts bytes, not characters.

## Supported platforms

| Platform | Notes |
|---|---|
| **macOS** | Full support including Apple Silicon P/E core detection, VideoCore/VRAM, `vm_stat` memory, `system_profiler` hardware data |
| **Linux (x86-64)** | Full support via `/proc/cpuinfo`, `free`, `lspci`, `/etc/os-release` |
| **Linux (ARM / Raspberry Pi)** | CPU from `lscpu` or `/proc/device-tree/model`; GPU identified by VideoCore generation (Pi 3/4/5) |
| **NetBSD** | Full support via `sysctl`, `swapctl`, `dmesg.boot` for GPU; `/sbin` and `/usr/sbin` are prepended to PATH automatically |

## Prerequisites

The script requires `bash` 4.0 or later and standard POSIX utilities. Most dependencies are part of the base OS install.

### macOS

| Tool | Source | Used for |
|---|---|---|
| `bash` | Pre-installed (or Homebrew) | Script interpreter |
| `sysctl` | Pre-installed | CPU, memory, swap |
| `system_profiler` | Pre-installed | GPU, model, serial, Xcode CLT |
| `vm_stat` | Pre-installed | Memory page statistics |
| `df` | Pre-installed | Disk usage |

### Linux

| Tool | Package | Used for |
|---|---|---|
| `bash` | `bash` | Script interpreter |
| `free` | `procps` / `procps-ng` | Memory and swap |
| `nproc` | `coreutils` | CPU core count |
| `lscpu` | `util-linux` | CPU model (ARM fallback) |
| `lspci` | `pciutils` | GPU detection (optional — not available on ARM) |
| `df` | `coreutils` | Disk usage |

### NetBSD

| Tool | Source | Used for |
|---|---|---|
| `bash` | `shells/bash` (pkgsrc) | Script interpreter |
| `sysctl` | Base system (`/sbin/sysctl`) | CPU, memory, hardware info |
| `swapctl` | Base system (`/sbin/swapctl`) | Swap usage |
| `df` | Base system | Disk usage |

> **Note:** NetBSD's `sysctl`, `ifconfig`, and `swapctl` live in `/sbin` and `/usr/sbin`, which may not be in the PATH of non-interactive shells. The script prepends these directories automatically.

### Optional tools (all platforms)

The Build Environment section checks for these tools and reports ✓/✗ — they are not required to run the script:

`make`, `gmake`, `cmake`, `ninja`, `pkg-config`, `autoconf`, `automake`, `libtool`, `git`, `openssl`, `node`, `npm`

## Usage

```bash
chmod +x justTheFacts.sh
./justTheFacts.sh
```

The script clears the terminal before rendering and requires a terminal that supports 256-colour ANSI escape codes and UTF-8.
