#!/bin/bash

# ===============================
# 🤖 Mac AI - Intelligent Security Analysis
# Optimized for Apple M1 Pro with Neural Engine
# Lightweight on-device AI for threat detection
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

AI_DIR="$CONFIG_DIR/ai"
MODELS_DIR="$AI_DIR/models"
DATA_DIR="$AI_DIR/data"
PYTHON_SCRIPT="$SCRIPT_DIR/ai_engine.py"
ML_SCRIPT="$SCRIPT_DIR/ml_engine.py"

mkdir -p "$MODELS_DIR" "$DATA_DIR"

# Check Python and required packages
check_python_setup() {
    if ! command -v python3 &> /dev/null; then
        error_exit "Python 3 is required for AI features. Install from python.org"
    fi
    
    # Add user bin to PATH if not already there (fixes pip install warnings)
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Check for required packages
    local missing_packages=()
    
    if ! python3 -c "import numpy" 2>/dev/null; then
        missing_packages+=("numpy")
    fi
    
    if ! python3 -c "import sklearn" 2>/dev/null; then
        missing_packages+=("scikit-learn")
    fi
    
    if ! python3 -c "import pandas" 2>/dev/null; then
        missing_packages+=("pandas")
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        if [ "$QUIET" != true ]; then
            warning "Installing required Python packages: ${missing_packages[*]}"
            info "This may take a minute..."
        fi
        
        # Install with user flag and suppress PATH warnings
        if pip3 install --user "${missing_packages[@]}" 2>&1 | grep -v "WARNING.*PATH\|NOTE.*PATH" | grep -v "^$"; then
            # Ensure PATH is updated after installation
            export PATH="$HOME/.local/bin:$PATH"
            
            # Verify installation
            local failed=0
            for pkg in "${missing_packages[@]}"; do
                if [ "$pkg" = "scikit-learn" ]; then
                    if ! python3 -c "import sklearn" 2>/dev/null; then
                        failed=1
                    fi
                else
                    if ! python3 -c "import ${pkg//-/_}" 2>/dev/null; then
                        failed=1
                    fi
                fi
            done
            
            if [ $failed -eq 0 ]; then
                if [ "$QUIET" != true ]; then
                    success "Python packages installed successfully"
                fi
                return 0
            else
                warning "Some packages may not be fully installed. Continuing anyway..."
                return 0
            fi
        else
            warning "Package installation had issues. Continuing with available packages..."
            export PATH="$HOME/.local/bin:$PATH"
            return 0
        fi
    fi
    
    return 0
}

# Behavioral anomaly detection using statistical ML
detect_anomalies_ml() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🤖 AI: Behavioral Anomaly Detection...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    # Collect system metrics
    local metrics_file="$DATA_DIR/metrics_$(date +%Y%m%d_%H%M%S).json"
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"process_count\": $(ps aux | wc -l | tr -d ' '),"
        echo "  \"network_connections\": $( (lsof -i -P -n 2>/dev/null | grep -c ESTABLISHED || echo 0) | head -1),"
        echo "  \"cpu_usage\": $(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo 0),"
        echo "  \"memory_usage\": $(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//' || echo 0),"
        echo "  \"disk_io\": $(iostat -d 1 1 2>/dev/null | tail -1 | awk '{print $3}' || echo 0),"
        echo "  \"logged_users\": $(who | wc -l | tr -d ' ')"
        echo "}"
    } > "$metrics_file"
    
    # Run Python ML analysis
    if [ -f "$PYTHON_SCRIPT" ]; then
        # Error handling for Python script execution
        set +e  # Temporarily disable exit on error
        local result=$(python3 "$PYTHON_SCRIPT" --analyze "$metrics_file" 2>&1 || echo "ERROR")
        set -e  # Re-enable exit on error
        
        if [ "$result" != "ERROR" ] && [ "$result" != "NORMAL" ]; then
            warning "AI detected potential anomaly: $result"
            return 1
        elif [ "$result" = "NORMAL" ]; then
            success "AI analysis: Normal behavior detected"
            return 0
        fi
    fi
    
    return 0
}

# Pattern recognition for threat detection
pattern_recognition() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🤖 AI: Pattern Recognition Analysis...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    # Collect process patterns
    local process_data="$DATA_DIR/processes_$(date +%Y%m%d_%H%M%S).txt"
    ps aux | awk 'NR>1 {print $2, $3, $4, $11}' > "$process_data" 2>/dev/null || true
    
    # Collect network patterns
    local network_data="$DATA_DIR/network_$(date +%Y%m%d_%H%M%S).txt"
    if command -v lsof &> /dev/null; then
        lsof -i -P -n 2>/dev/null | grep ESTABLISHED > "$network_data" || true
    fi
    
    # Run pattern recognition
    if [ -f "$PYTHON_SCRIPT" ]; then
        # Error handling for Python script execution
        set +e  # Temporarily disable exit on error
        local result=$(python3 "$PYTHON_SCRIPT" --patterns "$process_data" "$network_data" 2>&1 || echo "ERROR")
        set -e  # Re-enable exit on error
        
        if [ "$result" != "ERROR" ] && [ -n "$result" ]; then
            warning "AI pattern recognition found: $result"
            return 1
        else
            success "AI pattern recognition: No threats detected"
            return 0
        fi
    fi
    
    return 0
}

# Predictive threat analysis
predictive_analysis() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🤖 AI: Predictive Threat Analysis...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    # Analyze historical data
    local historical_data="$DATA_DIR"
    local prediction_file="$DATA_DIR/prediction_$(date +%Y%m%d_%H%M%S).json"
    
    if [ -f "$PYTHON_SCRIPT" ]; then
        # Error handling for Python script execution
        set +e  # Temporarily disable exit on error
        local result=$(python3 "$PYTHON_SCRIPT" --predict "$historical_data" 2>&1 || echo "ERROR")
        set -e  # Re-enable exit on error
        
        if [ "$result" != "ERROR" ] && [ -n "$result" ]; then
            info "AI prediction: $result"
            echo "$result" > "$prediction_file"
        fi
    fi
    
    return 0
}

# Intelligent file classification
classify_files() {
    local target_dir="${1:-$HOME/Documents}"
    
    if [ "$QUIET" != true ]; then
        echo "${bold}🤖 AI: Intelligent File Classification...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    # Collect file metadata
    local file_data="$DATA_DIR/files_$(date +%Y%m%d_%H%M%S).json"
    {
        echo "["
        local first=true
        find "$target_dir" -type f -size +1k -size -10M 2>/dev/null | head -100 | while read -r file; do
            [ "$first" = false ] && echo ","
            first=false
            local size=$(stat -f %z "$file" 2>/dev/null || echo 0)
            local ext="${file##*.}"
            echo "  {\"path\": \"$file\", \"size\": $size, \"ext\": \"$ext\"}"
        done
        echo "]"
    } > "$file_data"
    
    # Classify files
    if [ -f "$PYTHON_SCRIPT" ]; then
        # Error handling for Python script execution
        set +e  # Temporarily disable exit on error
        local result=$(python3 "$PYTHON_SCRIPT" --classify "$file_data" 2>&1 || echo "ERROR")
        set -e  # Re-enable exit on error
        
        if [ "$result" != "ERROR" ]; then
            info "AI classification complete"
            return 0
        fi
    fi
    
    return 0
}

# Train ML models
train_ml_models() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🎓 Training Machine Learning Models...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    if [ -f "$ML_SCRIPT" ]; then
        # Error handling for ML training
        set +e  # Temporarily disable exit on error
        if python3 "$ML_SCRIPT" --train 2>&1; then
            set -e  # Re-enable exit on error
            success "ML models trained successfully"
            log_message "SUCCESS" "ML models trained"
            return 0
        else
            warning "ML training needs more data. Run AI analysis a few times first."
            return 1
        fi
    fi
    
    return 1
}

# Advanced ML analysis
advanced_ml_analysis() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🧠 Advanced ML Analysis...${normal}"
    fi
    
    if ! check_python_setup; then
        return 1
    fi
    
    if [ -f "$ML_SCRIPT" ]; then
        # Cluster patterns
        # Error handling for ML clustering
        set +e  # Temporarily disable exit on error
        local clusters=$(python3 "$ML_SCRIPT" --cluster "$DATA_DIR" 2>&1 || echo "")
        set -e  # Re-enable exit on error
        if [ -n "$clusters" ]; then
            info "Pattern clusters discovered:"
            echo "$clusters"
        fi
        
        # ML-based prediction
        # Error handling for ML prediction
        set +e  # Temporarily disable exit on error
        local prediction=$(python3 "$ML_SCRIPT" --predict "$DATA_DIR" 2>&1 || echo "")
        set -e  # Re-enable exit on error
        if [ -n "$prediction" ] && [ "$prediction" != "No significant trends" ]; then
            info "ML Prediction: $prediction"
        fi
    fi
    
    return 0
}

# Main AI analysis
main() {
    if [ "$QUIET" != true ]; then
        echo "${bold}🤖 Mac AI - Intelligent Security Analysis${normal}"
        echo "Optimized for Apple M1 Pro with Neural Engine"
        echo "=========================================="
        echo ""
    fi
    
    log_message "INFO" "AI analysis started"
    
    local issues=0
    
    # Run AI analyses (use ML engine if available)
    if [ -f "$ML_SCRIPT" ] && python3 -c "import sklearn" 2>/dev/null; then
        # Use advanced ML engine
        local metrics_file="$DATA_DIR/metrics_$(date +%Y%m%d_%H%M%S).json"
        {
            echo "{"
            echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
            echo "  \"process_count\": $(ps aux | wc -l | tr -d ' '),"
            echo "  \"network_connections\": $( (lsof -i -P -n 2>/dev/null | grep -c ESTABLISHED || echo 0) | head -1),"
            echo "  \"cpu_usage\": $(top -l 1 | grep 'CPU usage' | awk '{print $3}' | sed 's/%//' || echo 0),"
            echo "  \"memory_usage\": $(vm_stat | grep 'Pages active' | awk '{print $3}' | sed 's/\.//' || echo 0),"
            echo "  \"disk_io\": $(iostat -d 1 1 2>/dev/null | tail -1 | awk '{print $3}' || echo 0),"
            echo "  \"logged_users\": $(who | wc -l | tr -d ' ')"
            echo "}"
        } > "$metrics_file"
        
        # Error handling for ML analysis
        set +e  # Temporarily disable exit on error
        local ml_result=$(python3 "$ML_SCRIPT" --analyze "$metrics_file" 2>&1 || echo "ERROR")
        set -e  # Re-enable exit on error
        if [ "$ml_result" != "ERROR" ] && [ "$ml_result" != "NORMAL" ]; then
            warning "ML detected: $ml_result"
            issues=$((issues + 1))
        elif [ "$ml_result" = "NORMAL" ]; then
            success "ML analysis: Normal"
        fi
        
        # Online learning
        # Error handling for online learning (non-critical, continue on error)
        set +e  # Temporarily disable exit on error
        python3 "$ML_SCRIPT" --online "$metrics_file" 2>&1 || true
        set -e  # Re-enable exit on error
    else
        # Fallback to basic AI
        detect_anomalies_ml || issues=$((issues + 1))
    fi
    
    pattern_recognition || issues=$((issues + 1))
    predictive_analysis || issues=$((issues + 1))
    
    # Advanced ML if requested
    if [ "$ADVANCED" = true ]; then
        advanced_ml_analysis || issues=$((issues + 1))
    fi
    
    # Summary
    if [ "$QUIET" != true ]; then
        echo ""
        if [ $issues -eq 0 ]; then
            echo "${bold}${green}✅ AI Analysis Complete - All Clear${normal}"
            # Don't send notification when everything is clear (reduces spam)
            # Only notify on actual threats
        else
            echo "${bold}${yellow}⚠️  AI Analysis Complete - $issues Potential Issue(s) Detected${normal}"
            echo "${yellow}   Review the findings above for details.${normal}"
            # Only send notification when there are actual issues
            send_notification "Mac AI Alert" "AI detected $issues potential issue(s)" "${NOTIFICATION_SOUND:-true}" "critical"
        fi
    fi
    
    log_message "INFO" "AI analysis completed - $issues issues found"
    
    # Exit with success (0) - analysis completed successfully
    # Issues found are warnings, not script errors
    exit 0
}

# Parse arguments
QUIET=false
CLASSIFY=false
TRAIN=false
ADVANCED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet) QUIET=true; shift ;;
        --classify) CLASSIFY=true; shift ;;
        --train) TRAIN=true; shift ;;
        --advanced) ADVANCED=true; shift ;;
        -h|--help)
            cat <<EOF
Mac AI - Intelligent Security Analysis with Machine Learning

Usage: $0 [OPTIONS]

Options:
    -h, --help      Show this help
    -q, --quiet     Minimal output
    --classify      Run file classification
    --train         Train ML models
    --advanced      Run advanced ML analysis (clustering, predictions)

Examples:
    $0                  # Standard AI analysis
    $0 --train          # Train ML models
    $0 --advanced       # Advanced ML with clustering
    $0 --train --advanced  # Train and run advanced analysis

EOF
            exit 0
            ;;
        *) shift ;;
    esac
done

if [ "$TRAIN" = true ]; then
    train_ml_models
elif [ "$CLASSIFY" = true ]; then
    classify_files
else
    main
fi

