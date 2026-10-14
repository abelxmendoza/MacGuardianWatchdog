#!/bin/bash

# ===============================
# 🔵 Mac Blue Team v1.0
# Advanced Threat Detection & Response
# Enterprise-grade security monitoring
# ===============================

set -euo pipefail

# Global error handler
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    # Only log if it's a real error (not from a function that returns non-zero intentionally)
    if [ $exit_code -ne 0 ] && [ "${CONTINUE_ON_ERROR:-false}" != "true" ]; then
        log_message "ERROR" "Script error at line $line_no (exit code: $exit_code)"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"

# Blue Team specific config
BLUETEAM_DIR="$CONFIG_DIR/blueteam"
THREAT_INTEL_DB="$BLUETEAM_DIR/threat_intel.json"
BEHAVIORAL_BASELINE="$BLUETEAM_DIR/behavioral_baseline.json"
INCIDENT_LOG="$BLUETEAM_DIR/incidents.log"
THREAT_HUNT_RESULTS="$BLUETEAM_DIR/threat_hunt_$(date +%Y%m%d).json"

mkdir -p "$BLUETEAM_DIR"

# Parse arguments
QUIET=false
VERBOSE=false
THREAT_HUNT=false
FORENSIC_MODE=false
USE_OSQUERY=false
USE_NMAP=false
USE_YARA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --threat-hunt) THREAT_HUNT=true; shift ;;
        --forensic) FORENSIC_MODE=true; shift ;;
        --osquery) USE_OSQUERY=true; shift ;;
        --nmap) USE_NMAP=true; shift ;;
        --yara) USE_YARA=true; shift ;;
        -h|--help)
            cat <<EOF
Mac Blue Team - Advanced Threat Detection

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help
    -q, --quiet         Minimal output
    -v, --verbose       Detailed output
    --threat-hunt       Run advanced threat hunting
    --forensic         Forensic analysis mode
    --osquery           Use osquery for advanced system queries
    --nmap              Run network port scanning
    --yara              Use yara for pattern matching

EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

# Initialize threat intelligence database
init_threat_intel() {
    if [ ! -f "$THREAT_INTEL_DB" ]; then
        cat > "$THREAT_INTEL_DB" <<EOF
{
  "suspicious_ips": [],
  "known_malware_hashes": [],
  "suspicious_domains": [],
  "ioc_patterns": [
    ".*\\.exe$",
    ".*\\.bat$",
    ".*\\.scr$",
    ".*powershell.*-enc",
    ".*base64.*decode"
  ],
  "suspicious_process_names": [
    "miner", "crypto", "bitcoin", "malware", "trojan", "backdoor"
  ],
  "suspicious_ports": [4444, 5555, 6666, 7777, 8888, 9999, 1337, 31337]
}
EOF
        success "Threat intelligence database initialized"
    fi
}

# Advanced process analysis
analyze_processes() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔍 Advanced Process Analysis...${normal}"
    fi
    
    local suspicious_count=0
    local processes=()
    
    # Get all processes with detailed info (limit to first 500 to avoid timeout)
    local process_count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            processes+=("$line")
            process_count=$((process_count + 1))
            # Limit to prevent timeout on systems with many processes
            if [ $process_count -ge 500 ]; then
                break
            fi
        fi
    done < <(ps -axo pid=,%cpu=,%mem=,comm= 2>/dev/null | head -500)
    
    # Check for suspicious patterns
    for proc in "${processes[@]}"; do
        local pid=$(echo "$proc" | awk '{print $1}')
        local cpu=$(echo "$proc" | awk '{print $2}')
        local mem=$(echo "$proc" | awk '{print $3}')
        # Full executable path (may contain spaces)
        local cmd=$(echo "$proc" | awk '{$1=$2=$3=""; sub(/^ +/, ""); print}')
        
        # High CPU/Memory usage (using awk for comparison)
        if [ -n "$cpu" ] && [ -n "$mem" ]; then
            local cpu_int=${cpu%.*}
            local mem_int=${mem%.*}
            
            # Only flag if CPU is consistently high (not just a spike)
            # Also exclude known system processes
            if [ "$cpu_int" -gt 50 ] 2>/dev/null; then
                # Skip known system processes
                if echo "$cmd" | grep -qiE "(biomesyncd|WindowServer|kernel_task|mds|mdworker|Spotlight|TimeMachine)"; then
                    # These are normal system processes, skip
                    continue
                fi
                warning "High CPU process: PID $pid ($cpu%) - $cmd"
                suspicious_count=$((suspicious_count + 1))
            fi
            
            # Only flag very high memory usage (not just moderate)
            if [ "$mem_int" -gt 30 ] 2>/dev/null; then
                # Skip known system processes
                if echo "$cmd" | grep -qiE "(kernel_task|WindowServer|Safari|Chrome|Firefox|Photos|Final Cut|Xcode)"; then
                    # These are normal high-memory apps, skip
                    continue
                fi
                warning "High memory process: PID $pid ($mem%) - $cmd"
                suspicious_count=$((suspicious_count + 1))
            fi
        fi
        
        # Check against threat intel (fallback if jq not available)
        local patterns=""
        if command -v jq &> /dev/null && [ -f "$THREAT_INTEL_DB" ]; then
            patterns=$(jq -r '.suspicious_process_names[]' "$THREAT_INTEL_DB" 2>/dev/null || echo "")
        else
            # Fallback to hardcoded patterns
            patterns="miner crypto bitcoin malware trojan backdoor"
        fi
        
        # Match the program's own name, not its folder: Malwarebytes lives in
        # ".../Malwarebytes/..." and must not be reported as "malware".
        local name
        name="$(basename "$cmd")"
        for pattern in $patterns; do
            if echo "$name" | grep -qi "$pattern"; then
                # macOS's read-only system volume and properly signed software
                # aren't dropped malware.
                case "$cmd" in /System/*|/usr/bin/*|/usr/sbin/*|/usr/libexec/*|/bin/*|/sbin/*) break ;; esac
                if [ -f "$cmd" ] && codesign --verify "$cmd" 2>/dev/null && \
                   codesign -dv --verbose=2 "$cmd" 2>&1 | grep -qE "Authority=(Developer ID Application|(macOS )?Software Signing|Apple Mac OS Application Signing)"; then
                    break
                fi
                warning "🚨 THREAT: Suspicious unsigned process matching IOC '$pattern' - PID $pid: $cmd"
                log_message "CRITICAL" "Suspicious process matching IOC - PID $pid: $cmd"
                suspicious_count=$((suspicious_count + 1))
                break
            fi
        done
    done
    
    if [ $suspicious_count -eq 0 ]; then
        success "No suspicious processes detected"
    fi
    
    log_message "INFO" "Process analysis completed - $suspicious_count suspicious items"
    return $suspicious_count
}

# Network traffic analysis
# NOTE: This does NOT wiretap or inspect packet content
# It only checks connection metadata (IPs, ports, process names)
analyze_network() {
    # Check privacy mode
    if [ -f "$SCRIPT_DIR/privacy_mode.sh" ]; then
        source "$SCRIPT_DIR/privacy_mode.sh" 2>/dev/null || true
        load_privacy_settings 2>/dev/null || true
        if [ "${MONITOR_NETWORK:-true}" = "false" ]; then
            info "Network monitoring disabled (privacy mode)"
            return 0
        fi
    fi
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🌐 Network Traffic Analysis...${normal}"
        echo "${blue}   (Connection metadata only - no packet inspection)${normal}"
    fi
    
    local suspicious_conns=0
    
    if ! command -v lsof &> /dev/null; then
        warning "lsof not available - skipping network analysis"
        return 1
    fi
    
    # Get all network connections
    # NOTE: lsof only shows connection metadata (like netstat)
    # This is NOT wiretapping - we don't capture or inspect packet content
    local connections=$(lsof -i -P -n 2>/dev/null | grep ESTABLISHED || true)
    
    if [ -z "$connections" ]; then
        info "No active network connections"
        return 0
    fi
    
    # Check threat intelligence database
    local threat_intel_db="$HOME/.macguardian/threat_intel/iocs.json"
    
    # Analyze connections
    while IFS= read -r conn; do
        if [ -z "$conn" ]; then continue; fi
        
        local port=$(echo "$conn" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        local remote=$(echo "$conn" | awk '{print $9}' | cut -d: -f1)
        
        # Check suspicious ports
        local sus_ports=""
        if command -v jq &> /dev/null && [ -f "$THREAT_INTEL_DB" ]; then
            sus_ports=$(jq -r '.suspicious_ports[]' "$THREAT_INTEL_DB" 2>/dev/null || echo "")
        else
            # Fallback to common suspicious ports
            sus_ports="4444 5555 6666 7777 8888 9999 1337 31337"
        fi
        
        for sus_port in $sus_ports; do
            if [ "$port" = "$sus_port" ]; then
                warning "🚨 Suspicious port connection: $remote:$port"
                echo "$conn" >> "$INCIDENT_LOG"
                suspicious_conns=$((suspicious_conns + 1))
            fi
        done
        
        # Check against threat intelligence feeds
        if [ -f "$threat_intel_db" ] && command -v jq &> /dev/null; then
            # Check if IP is in threat intel database
            local threat_match=$(jq -r ".[] | select(.type == \"ip\" and .value == \"$remote\") | .value" "$threat_intel_db" 2>/dev/null | head -1)
            if [ -n "$threat_match" ]; then
                local threat_source=$(jq -r ".[] | select(.type == \"ip\" and .value == \"$remote\") | .source" "$threat_intel_db" 2>/dev/null | head -1)
                error_exit "🚨 CRITICAL: Connection to known malicious IP: $remote (source: ${threat_source:-threat_intel})"
                suspicious_conns=$((suspicious_conns + 1))
            fi
        fi
        
        # Check against known bad IPs (legacy format)
        if [ -f "$THREAT_INTEL_DB" ]; then
            local bad_ips=""
            if command -v jq &> /dev/null; then
                bad_ips=$(jq -r '.suspicious_ips[]' "$THREAT_INTEL_DB" 2>/dev/null || echo "")
            fi
            
            for bad_ip in $bad_ips; do
                if [ "$remote" = "$bad_ip" ]; then
                    error_exit "🚨 CRITICAL: Connection to known malicious IP: $bad_ip"
                    suspicious_conns=$((suspicious_conns + 1))
                fi
            done
        fi
    done <<< "$connections"
    
    if [ $suspicious_conns -eq 0 ]; then
        success "No suspicious network connections detected"
    else
        warning "Found $suspicious_conns suspicious connection(s)"
    fi
    
    log_message "INFO" "Network analysis completed - $suspicious_conns suspicious connections"
    return $suspicious_conns
}

# File system anomaly detection
detect_filesystem_anomalies() {
    if [ "$QUIET" != true ]; then
        echo "${bold}📁 File System Anomaly Detection...${normal}"
    fi
    
    local anomalies=0
    
    # Check for recently modified system files (exclude known safe paths)
    # Optimized: Only check critical system directories that are security-relevant
    # Focus on launch agents/daemons and user-installed binaries (most likely attack vectors)
    local recent_system_files=$(find /System/Library/LaunchDaemons /System/Library/LaunchAgents /usr/local/bin /usr/local/sbin -type f -mtime -7 \
        -not -path "*/AssetsV2/*" \
        -not -path "*/MobileAsset/*" \
        -not -path "*/Caches/*" \
        -not -path "*/Logs/*" \
        -not -path "*/Preferences/*" \
        -not -path "*/Application Support/*" \
        -not -path "*/Volumes/Update/*" \
        -not -path "*/Volumes/Hardware/*" \
        -not -path "*/Volumes/Preboot/*" \
        -not -path "*/Volumes/Data/Library/Apple/System/Library/Receipts/*" \
        -not -path "*/Receipts/*" \
        2>/dev/null | head -20 || true)
    
    if [ -n "$recent_system_files" ]; then
        warning "Recently modified system files detected (excluding known safe paths):"
        echo "$recent_system_files" | while read -r file; do
            if [ -n "$file" ]; then
                local mod_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null || echo "unknown")
                warning "  • $file (modified: $mod_time)"
                anomalies=$((anomalies + 1))
            fi
        done
    fi
    
    # Check for hidden executable files (exclude config files and known safe files)
    local hidden_executables=$(find "$HOME" -maxdepth 3 -type f -name ".*" -perm +111 \
        -not -path "*/Library/Caches/*" \
        -not -path "*/Library/Application Support/*" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -name ".gitignore" \
        -not -name ".eslintrc*" \
        -not -name ".prettierrc*" \
        -not -name ".env*" \
        -not -name ".*rc" \
        -not -name ".*config*" \
        2>/dev/null | head -10 || true)
    
    if [ -n "$hidden_executables" ]; then
        warning "Hidden executable files found (excluding config files):"
        echo "$hidden_executables" | while read -r file; do
            if [ -n "$file" ]; then
                warning "  • $file"
                anomalies=$((anomalies + 1))
            fi
        done
    fi
    
    # Check for files with suspicious extensions (exclude known safe locations)
    for ext in .exe .bat .scr .vbs .ps1; do
        local suspicious=$(find "$HOME" -maxdepth 4 -type f -name "*$ext" \
            -not -path "*/Library/Caches/*" \
            -not -path "*/Library/Application Support/*" \
            -not -path "*/.git/*" \
            -not -path "*/node_modules/*" \
            -not -path "*/Downloads/*" \
            -not -path "*/Applications/*" \
            -not -path "*/Development/*" \
            -not -path "*/Projects/*" \
            -not -path "*/Others/*" \
            -not -path "*/.cursor/*" \
            -not -path "*/.vscode/*" \
            -not -path "*/.expo/*" \
            2>/dev/null | head -5 || true)
        if [ -n "$suspicious" ]; then
            warning "Files with suspicious extension ($ext) in unexpected locations:"
            echo "$suspicious" | while read -r file; do
                if [ -n "$file" ]; then
                    warning "  • $file"
                    anomalies=$((anomalies + 1))
                fi
            done
        fi
    done
    
    # .sh files are usually legitimate on macOS, only flag if in suspicious locations
    # Exclude: caches, dev tools, known safe directories, and files directly in $HOME
    local suspicious_sh=$(find "$HOME" -maxdepth 4 -type f -name "*.sh" \
        -not -path "*/Library/Caches/*" \
        -not -path "*/Library/Application Support/*" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/Development/*" \
        -not -path "*/Projects/*" \
        -not -path "*/Desktop/*" \
        -not -path "*/Documents/*" \
        -not -path "*/.cursor/*" \
        -not -path "*/.vscode/*" \
        -not -path "*/.expo/*" \
        -not -path "*/.nvm/*" \
        -not -path "*/VirtualBox VMs/*" \
        -exec sh -c 'test "$(dirname "$1")" != "$2"' _ {} "$HOME" \; \
        2>/dev/null | head -5 || true)
    if [ -n "$suspicious_sh" ]; then
        warning "Shell scripts (.sh) in unexpected locations:"
        echo "$suspicious_sh" | while read -r file; do
            if [ -n "$file" ]; then
                warning "  • $file"
                anomalies=$((anomalies + 1))
            fi
        done
    fi
    
    if [ $anomalies -eq 0 ]; then
        success "No file system anomalies detected"
    else
        warning "Found $anomalies file system anomaly/ies"
    fi
    
    log_message "INFO" "File system analysis completed - $anomalies anomalies"
    return $anomalies
}

# Behavioral analysis
behavioral_analysis() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🧠 Behavioral Analysis...${normal}"
    fi
    
    # Baseline system behavior
    if [ ! -f "$BEHAVIORAL_BASELINE" ]; then
        info "Creating behavioral baseline..."
        
        local proc_count=$(ps aux | wc -l | tr -d ' ')
    local net_conns=$( (lsof -i -P -n 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' ' || echo "0") | head -1)
    local users=$( (who | wc -l | tr -d ' ' || echo "0") | head -1)
    local load=$(uptime | awk -F'load averages:' '{print $2}' | xargs || echo "unknown")
    
    local baseline_data=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "process_count": $proc_count,
  "network_connections": $net_conns,
  "logged_in_users": $users,
  "system_load": "$load"
}
EOF
        )
        echo "$baseline_data" > "$BEHAVIORAL_BASELINE"
        success "Behavioral baseline created"
        return 0
    fi
    
    # Compare current behavior to baseline
    local current_processes=$(ps aux | wc -l | tr -d ' ')
    local baseline_processes=""
    
    if command -v jq &> /dev/null && [ -f "$BEHAVIORAL_BASELINE" ]; then
        baseline_processes=$(jq -r '.process_count' "$BEHAVIORAL_BASELINE" 2>/dev/null || echo "$current_processes")
    else
        # Fallback: extract from JSON manually or use current
        baseline_processes=$(grep -o '"process_count":[0-9]*' "$BEHAVIORAL_BASELINE" 2>/dev/null | cut -d: -f2 || echo "$current_processes")
    fi
    
    if [ -z "$baseline_processes" ] || [ "$baseline_processes" = "null" ]; then
        baseline_processes="$current_processes"
    fi
    
    local diff=$((current_processes - baseline_processes))
    local percent_diff=0
    if [ "$baseline_processes" -gt 0 ] 2>/dev/null; then
        percent_diff=$((diff * 100 / baseline_processes))
    fi
    
    if [ ${percent_diff#-} -gt 50 ]; then
        warning "Significant process count deviation: $current_processes vs baseline $baseline_processes ($percent_diff% change)"
        log_message "WARNING" "Behavioral anomaly: Process count deviation"
        return 1
    else
        success "Behavioral analysis: Normal"
        return 0
    fi
}

# Threat hunting mode
threat_hunt() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🎯 Advanced Threat Hunting...${normal}"
    fi
    
    local findings=0
    
    # Hunt for persistence mechanisms
    if [ "$QUIET" != true ]; then
        echo "  • Checking launch agents..."
    fi
    local suspicious_agents=$(find "$HOME/Library/LaunchAgents" -type f -mtime -30 2>/dev/null || true)
    if [ -n "$suspicious_agents" ]; then
        warning "Recent launch agents found:"
        echo "$suspicious_agents"
        findings=$((findings + 1))
    fi
    
    # Hunt for cron jobs
    if [ "$QUIET" != true ]; then
        echo "  • Checking cron jobs..."
    fi
    local cron_jobs=$(crontab -l 2>/dev/null || true)
    if [ -n "$cron_jobs" ]; then
        info "Active cron jobs found - review manually"
        echo "$cron_jobs"
    fi
    
    # Hunt for suspicious file modifications
    if [ "$QUIET" != true ]; then
        echo "  • Hunting for suspicious file modifications..."
    fi
    local recent_mods=$(find "$HOME" -type f -mtime -1 -size +1M 2>/dev/null | head -10 || true)
    if [ -n "$recent_mods" ]; then
        info "Large files modified in last 24h:"
        echo "$recent_mods"
    fi
    
    # Hunt for encoded/obfuscated content
    if [ "$QUIET" != true ]; then
        echo "  • Hunting for obfuscated content..."
    fi
    local encoded=$(find "$HOME" -type f -name "*.txt" -exec grep -l "base64\|eval\|exec\|decode" {} \; 2>/dev/null | head -5 || true)
    if [ -n "$encoded" ]; then
        warning "Files with potential obfuscation found:"
        echo "$encoded"
        findings=$((findings + 1))
    fi
    
    if [ $findings -eq 0 ]; then
        success "Threat hunt completed - no significant findings"
    else
        warning "Threat hunt found $findings potential issue(s)"
    fi
    
    log_message "INFO" "Threat hunt completed - $findings findings"
    return $findings
}

# Osquery-based system analysis
osquery_analysis() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔍 Osquery System Analysis...${normal}"
    fi
    
    # Check if osquery is installed
    if ! command -v osqueryi &> /dev/null; then
        if [ "$QUIET" != true ]; then
            warning "Osquery not found. Installing..."
        fi
        
        set +e
        if brew install osquery 2>&1; then
            set -e
            success "Osquery installed successfully"
        else
            set -e
            warning "Osquery installation failed. Skipping osquery analysis"
            return 1
        fi
    fi
    
    local issues=0
    local osquery_output="$BLUETEAM_DIR/osquery_$(date +%Y%m%d_%H%M%S).txt"
    
    # Run osquery queries
    if [ "$QUIET" != true ]; then
        echo "  • Querying system processes..."
    fi
    
    set +e
    osqueryi --line "SELECT pid, name, path, cpu_time, resident_size FROM processes WHERE cpu_time > 1000 ORDER BY cpu_time DESC LIMIT 10;" >> "$osquery_output" 2>&1
    
    if [ "$QUIET" != true ]; then
        echo "  • Querying network connections..."
    fi
    osqueryi --line "SELECT pid, local_address, local_port, remote_address, remote_port, state FROM process_open_sockets WHERE state = 'ESTABLISHED' LIMIT 20;" >> "$osquery_output" 2>&1
    
    if [ "$QUIET" != true ]; then
        echo "  • Querying listening ports..."
    fi
    osqueryi --line "SELECT pid, port, protocol, family, address FROM listening_ports LIMIT 20;" >> "$osquery_output" 2>&1
    
    if [ "$VERBOSE" = true ] && [ -f "$osquery_output" ]; then
        cat "$osquery_output"
    fi
    
    set -e
    
    success "Osquery analysis completed - Results: $osquery_output"
    log_message "INFO" "Osquery analysis completed"
    return 0
}

# Nmap network scanning
nmap_scan() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🌐 Network Port Scanning (Nmap)...${normal}"
    fi
    
    # Check if nmap is installed
    if ! command -v nmap &> /dev/null; then
        if [ "$QUIET" != true ]; then
            warning "Nmap not found. Installing..."
        fi
        
        set +e
        if brew install nmap 2>&1; then
            set -e
            success "Nmap installed successfully"
        else
            set -e
            warning "Nmap installation failed. Skipping network scan"
            return 1
        fi
    fi
    
    local issues=0
    local nmap_output="$BLUETEAM_DIR/nmap_scan_$(date +%Y%m%d_%H%M%S).txt"
    
    # Scan localhost for open ports
    if [ "$QUIET" != true ]; then
        echo "  • Scanning localhost for open ports..."
    fi
    
    set +e
    if nmap -sS -O localhost 2>&1 | tee "$nmap_output"; then
        set -e
        # Check for suspicious open ports
        local suspicious_ports=$(grep -E "^(4444|5555|6666|7777|8888|9999|1337|31337)/" "$nmap_output" 2>/dev/null || true)
        if [ -n "$suspicious_ports" ]; then
            warning "Suspicious open ports detected:"
            echo "$suspicious_ports"
            issues=$((issues + 1))
            log_message "WARNING" "Suspicious ports found via nmap"
        else
            success "No suspicious ports detected"
        fi
    else
        set -e
        warning "Nmap scan encountered issues"
        return 1
    fi
    
    success "Nmap scan completed - Results: $nmap_output"
    log_message "INFO" "Nmap scan completed"
    return $issues
}

# Yara pattern matching
yara_scan() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔎 Yara Pattern Matching...${normal}"
    fi
    
    # Check if yara is installed
    if ! command -v yara &> /dev/null; then
        if [ "$QUIET" != true ]; then
            warning "Yara not found. Installing..."
        fi
        
        set +e
        if brew install yara 2>&1; then
            set -e
            success "Yara installed successfully"
        else
            set -e
            warning "Yara installation failed. Skipping yara scan"
            return 1
        fi
    fi
    
    # Create basic yara rules file if it doesn't exist
    local yara_rules="$BLUETEAM_DIR/yara_rules.yar"
    if [ ! -f "$yara_rules" ]; then
        cat > "$yara_rules" <<'YARAEOF'
rule SuspiciousBase64 {
    strings:
        $base64 = /[A-Za-z0-9+\/]{100,}={0,2}/
    condition:
        $base64
}

rule SuspiciousExec {
    strings:
        $exec = /exec\(|eval\(|system\(/
    condition:
        $exec
}

rule CryptoMiner {
    strings:
        $miner1 = "miner"
        $miner2 = "cryptocurrency"
        $miner3 = "bitcoin"
    condition:
        any of them
}
YARAEOF
        info "Created default yara rules: $yara_rules"
    fi
    
    local issues=0
    local yara_output="$BLUETEAM_DIR/yara_scan_$(date +%Y%m%d_%H%M%S).txt"
    local scan_target="${SCAN_DIR:-$HOME/Documents}"
    
    if [ ! -d "$scan_target" ]; then
        warning "Scan target not found: $scan_target"
        return 1
    fi
    
    if [ "$QUIET" != true ]; then
        echo "  • Scanning $scan_target with yara rules..."
    fi
    
    set +e
    if yara -r "$yara_rules" "$scan_target" 2>&1 | tee "$yara_output"; then
        set -e
        local matches=$( (grep -c "matches" "$yara_output" 2>/dev/null || echo "0") | head -1)
        if [ "$matches" -gt 0 ]; then
            warning "Yara found $matches pattern match(es) - Review: $yara_output"
            issues=$((issues + 1))
            log_message "WARNING" "Yara found $matches matches"
        else
            success "No yara pattern matches found"
        fi
    else
        set -e
        warning "Yara scan encountered issues"
        return 1
    fi
    
    success "Yara scan completed - Results: $yara_output"
    log_message "INFO" "Yara scan completed"
    return $issues
}

# Forensic mode
forensic_analysis() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔬 Forensic Analysis Mode...${normal}"
    fi
    
    local forensic_dir="$BLUETEAM_DIR/forensic_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$forensic_dir"
    
    # Collect system information
    if [ "$QUIET" != true ]; then
        echo "  • Collecting system information..."
    fi
    {
        echo "=== SYSTEM INFORMATION ==="
        uname -a
        sw_vers
        echo ""
        echo "=== RUNNING PROCESSES ==="
        ps aux
        echo ""
        echo "=== NETWORK CONNECTIONS ==="
        lsof -i -P -n 2>/dev/null || echo "lsof not available"
        echo ""
        echo "=== OPEN FILES ==="
        lsof 2>/dev/null | head -100 || echo "lsof not available"
        echo ""
        echo "=== ENVIRONMENT VARIABLES ==="
        env
        echo ""
        echo "=== RECENT LOGIN ACTIVITY ==="
        last | head -20
    } > "$forensic_dir/system_snapshot.txt"
    
    # Collect file hashes
    if [ "$QUIET" != true ]; then
        echo "  • Collecting file hashes..."
    fi
    find "$HOME/Documents" -type f -exec shasum -a 256 {} \; 2>/dev/null > "$forensic_dir/file_hashes.txt" || true
    
    # Network capture info
    if [ "$QUIET" != true ]; then
        echo "  • Collecting network information..."
    fi
    {
        echo "=== NETSTAT ==="
        netstat -an 2>/dev/null || echo "netstat not available"
        echo ""
        echo "=== ROUTING TABLE ==="
        netstat -rn 2>/dev/null || echo "netstat not available"
    } > "$forensic_dir/network_info.txt" 2>/dev/null || true
    
    success "Forensic data collected: $forensic_dir"
    log_message "INFO" "Forensic analysis completed - data in $forensic_dir"
}

# Main execution
main() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🔵 Mac Blue Team - Advanced Threat Detection${normal}"
        echo "=========================================="
        echo ""
    fi
    
    log_message "INFO" "Blue Team analysis started"
    
    # Initialize
    init_threat_intel
    
    local total_issues=0
    
    # Initialize parallel processing
    if [ "${ENABLE_PARALLEL:-true}" = true ]; then
        init_parallel
        # Set longer timeout for Blue Team operations (filesystem scans can take time)
        export PARALLEL_JOB_TIMEOUT=90  # 90 seconds for Blue Team jobs
        if [ "$QUIET" != true ]; then
            info "Running analyses in parallel for faster execution"
        fi
        
    fi
    
    # Run analyses in parallel
    BLUETEAM_RESULTS="$BLUETEAM_DIR/analysis_results_$$.txt"
    > "$BLUETEAM_RESULTS"
    
    # Cleanup trap to kill any remaining background jobs on exit
    cleanup_parallel_jobs() {
        if [ ${#JOB_PIDS[@]} -gt 0 ]; then
            for pid in "${JOB_PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null || true
                fi
            done
            JOB_PIDS=()
            JOB_NAMES=()
            ACTIVE_JOBS=0
        fi
    }
    trap cleanup_parallel_jobs EXIT INT TERM
    
    if [ "${ENABLE_PARALLEL:-true}" = true ]; then
        # Export utility functions from utils.sh so they're available in subshells
        export -f warning success info error_exit log_message send_notification
        
        # Export analysis functions so they're available in subshells
        export -f analyze_processes analyze_network detect_filesystem_anomalies behavioral_analysis
        
        # Export variables needed by the functions
        export SCRIPT_DIR BLUETEAM_DIR THREAT_INTEL_DB QUIET VERBOSE BLUETEAM_RESULTS
        
        # Source utils.sh in each subshell to ensure all helper functions are available
        # The analysis functions are already exported, so they'll be available
        # Use run_parallel function for proper job management with output redirection
        run_parallel "process_analysis" "(source \"\$SCRIPT_DIR/utils.sh\" 2>/dev/null || true; analyze_processes) >> \"\$BLUETEAM_RESULTS\" 2>&1"
        run_parallel "network_analysis" "(source \"\$SCRIPT_DIR/utils.sh\" 2>/dev/null || true; analyze_network) >> \"\$BLUETEAM_RESULTS\" 2>&1"
        run_parallel "filesystem_analysis" "(source \"\$SCRIPT_DIR/utils.sh\" 2>/dev/null || true; detect_filesystem_anomalies) >> \"\$BLUETEAM_RESULTS\" 2>&1"
        run_parallel "behavioral_analysis" "(source \"\$SCRIPT_DIR/utils.sh\" 2>/dev/null || true; behavioral_analysis) >> \"\$BLUETEAM_RESULTS\" 2>&1"
        
        wait_all_jobs
        
        # Count issues from results (ensure it's a clean integer)
        total_issues=$( (grep -c "⚠️\|🚨\|THREAT\|CRITICAL" "$BLUETEAM_RESULTS" 2>/dev/null | tr -d ' \n' || echo "0") | head -1)
        total_issues=${total_issues:-0}
        
        # Always show results if there are issues, or if verbose mode
        if [ -f "$BLUETEAM_RESULTS" ]; then
            if [ "$VERBOSE" = true ]; then
                # Verbose: show everything
                cat "$BLUETEAM_RESULTS"
            elif [ "${total_issues:-0}" -gt 0 ]; then
                # Non-verbose but issues found: show warnings and errors
                echo ""
                echo "${bold}📋 Key Findings:${normal}"
                echo "----------------------------------------"
                # Show only warning/error lines, limit to first 30 for readability
                grep -E "⚠️|🚨|THREAT|CRITICAL|warning|Warning|WARNING|error|Error|ERROR" "$BLUETEAM_RESULTS" 2>/dev/null | head -30 || true
                if [ $total_issues -gt 30 ]; then
                    echo ""
                    echo "${yellow}... and $((total_issues - 30)) more issue(s) (use -v for full details)${normal}"
                fi
                echo ""
                # Save full results for later review
                local saved_results="$BLUETEAM_DIR/results_$(date +%Y%m%d_%H%M%S).txt"
                cp "$BLUETEAM_RESULTS" "$saved_results" 2>/dev/null || true
                echo "${cyan}💾 Full results saved to: $saved_results${normal}"
            else
                # No issues: just show success messages
                if [ "$QUIET" != true ]; then
                    grep -E "✅|success|Success|SUCCESS" "$BLUETEAM_RESULTS" 2>/dev/null | head -10 || true
                fi
            fi
        fi
        rm -f "$BLUETEAM_RESULTS"
    else
        # Sequential fallback
        analyze_processes || total_issues=$((total_issues + $?))
        analyze_network || total_issues=$((total_issues + $?))
        detect_filesystem_anomalies || total_issues=$((total_issues + $?))
        behavioral_analysis || total_issues=$((total_issues + $?))
    fi
    
    # Optional advanced modes
    if [ "$THREAT_HUNT" = true ]; then
        threat_hunt || total_issues=$((total_issues + $?))
    fi
    
    if [ "$FORENSIC_MODE" = true ]; then
        forensic_analysis
    fi
    
    # Advanced tool integrations
    if [ "$USE_OSQUERY" = true ]; then
        osquery_analysis || total_issues=$((total_issues + $?))
    fi
    
    if [ "$USE_NMAP" = true ]; then
        nmap_scan || total_issues=$((total_issues + $?))
    fi
    
    if [ "$USE_YARA" = true ]; then
        yara_scan || total_issues=$((total_issues + $?))
    fi
    
    # Summary
    if [ "$QUIET" != true ]; then
        echo ""
        if [ "${total_issues:-0}" -eq 0 ]; then
            echo "${bold}${green}✅ Blue Team Analysis Complete - No Threats Detected${normal}"
            # Don't send notification when everything is clear (reduces spam)
            # Only notify on actual threats
        else
            echo "${bold}${red}⚠️  Blue Team Analysis Complete - ${total_issues:-0} Issue(s) Detected${normal}"
            echo "${yellow}   Review the findings above for details.${normal}"
            echo ""
            echo "${cyan}💡 Tip: Run remediation to auto-fix issues:${normal}"
            echo "${cyan}   ./MacGuardianSuite/mac_remediation.sh --execute${normal}"
            # Only send notification when there are actual issues
            send_notification "Blue Team Alert" "$total_issues security issue(s) detected" "${NOTIFICATION_SOUND:-true}" "critical"
        fi
        echo ""
        echo "Detailed logs: $BLUETEAM_DIR"
        echo "Incident log: $INCIDENT_LOG"
    fi
    
    log_message "INFO" "Blue Team analysis completed - $total_issues issues found"
    
    # Populate Diamond Model from results
    if [ -f "$SCRIPT_DIR/diamond_model_correlation.sh" ] && [ -f "$BLUETEAM_RESULTS" ]; then
        source "$SCRIPT_DIR/diamond_model_correlation.sh" 2>/dev/null || true
        populate_from_blueteam "$BLUETEAM_RESULTS" 2>/dev/null || true
    fi
    
    # Send action-based email with AI summary
    if [ -f "$SCRIPT_DIR/action_email_notifier.sh" ] && [ -n "${REPORT_EMAIL:-${ALERT_EMAIL:-}}" ]; then
        source "$SCRIPT_DIR/action_email_notifier.sh" 2>/dev/null || true
        
        local event_data
        if [ "${total_issues:-0}" -gt 0 ]; then
            event_data=$(cat <<EOF
[
  {
    "category": "threat_detection",
    "severity": "$([ ${total_issues:-0} -gt 10 ] && echo "critical" || echo "high")",
    "title": "Blue Team threat detection completed",
    "description": "Detected ${total_issues:-0} security issue(s)",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "issues_count": ${total_issues:-0}
  }
]
EOF
)
            send_action_email "$ACTION_ISSUES_FOUND" "$event_data" 2>/dev/null || true
        else
            event_data=$(cat <<EOF
[
  {
    "category": "threat_detection",
    "severity": "info",
    "title": "Blue Team analysis complete - No threats",
    "description": "No security threats detected",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "issues_count": 0
  }
]
EOF
)
            send_action_email "$ACTION_SCAN_COMPLETE" "$event_data" 2>/dev/null || true
        fi
    fi
    
    # Exit with success (0) - analysis completed successfully
    # Issues found are warnings, not script errors
    exit 0
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

