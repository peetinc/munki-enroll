#!/bin/bash 

#######################################################################################
# Munki Enrollment Client Script
# Version: 2.0.0
# 
# Description:
#   Enrolls, updates, and maintains Munki manifests for macOS clients.
#   Uses standardized HTTP status codes for all server communication.
#   Automatically performs check-in when fetching manifests.
#
# Requirements:
#   - Must be run as root (for access to system preferences)
#   - Requires valid ManagedInstalls.plist with authentication credentials
#   - Server must have munki-enroll.php v2.0+ with HTTP status codes
#   - macOS 10.12 or later
#
# Exit Codes:
#   0  - Success
#   1  - General error (connection, validation, or unexpected issues)
#   2  - Manifest not found (404 error from server)
#   99 - UUID mismatch (403 error - security violation)
#
# Configuration:
#   Edit REPO_URL below to point to your Munki repository
#   Create plist at /var/root/Library/Preferences/tld.site.munki-enroll.plist
#   with catalog1-3 and manifest1-4 keys for customization
#
# Author: Artichoke Consulting
# Date: 2025.08.15
# License: MIT
#######################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures
IFS=$'\n\t'       # Set secure Internal Field Separator

#######################################################################################
## User Configuration - EDIT THIS SECTION
#######################################################################################

# REQUIRED: Change this URL to your Munki repository location
REPO_URL="https://munki.site.tld/repo"
ENROLL_URL="$REPO_URL/munki-enroll/munki-enroll.php"
PORT=443

# Enrollment configuration plist
# This plist contains catalog and manifest preferences
ENROLL_PLIST="tld.site.munki-enroll"

# Default values (can be overridden by plist)
# These will be sent to the server if set in the configuration plist
CATALOG1=""
CATALOG2=""
CATALOG3=""
MANIFEST1=""
MANIFEST2=""
MANIFEST3=""
MANIFEST4=""

#######################################################################################
## Script Configuration - DO NOT EDIT BELOW THIS LINE
#######################################################################################

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MUNKI_CONDITIONS_DIR="/usr/local/munki/conditions"
readonly MAX_CURL_TIME=15
readonly LOG_FILE="/var/log/munki-enroll/munki-enroll.log"

# Verbosity levels: 0=quiet (ERROR/SUCCESS only), 1=normal (no DEBUG), 2=debug (everything)
VERBOSITY_LEVEL=1  # Set to 0 for quiet, 1 for normal, 2 for debug

#######################################################################################
## Logging Functions
#######################################################################################

# Logging Function with 3-level verbosity and rotation
log_message() {
    local level="$1"
    local message="$2"
    
    # Rotate log if needed (10MB max size)
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$log_size" -gt 10485760 ]; then
            # Keep last 5 rotated logs
            for i in 4 3 2 1; do
                [ -f "${LOG_FILE}.$i" ] && mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
            done
            mv "$LOG_FILE" "${LOG_FILE}.1"
            # Remove oldest if it exists
            [ -f "${LOG_FILE}.5" ] && rm "${LOG_FILE}.5"
        fi
    fi
    
    # Always log to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    
    # Console output based on verbosity level
    case "$VERBOSITY_LEVEL" in
        0)  # Quiet - only ERROR and SUCCESS
            case "$level" in
                ERROR|SUCCESS)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
                    ;;
            esac
            ;;
        1)  # Normal - everything except DEBUG
            case "$level" in
                DEBUG)
                    # Skip DEBUG messages
                    ;;
                *)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
                    ;;
            esac
            ;;
        *)  # Debug mode (2 or higher) - show everything
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
            ;;
    esac
}

#######################################################################################
## Validation Functions
#######################################################################################

# Validate URL format
# Returns: 0 if valid, 1 if invalid (does not exit)
validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+(\:[0-9]+)?(/.*)?$ ]]; then
        log_message "ERROR" "Invalid URL format: $url"
        return 1
    fi
    return 0
}

# URL-encode a string for safe use in URLs
# Properly handles all special characters
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9])
                # These characters are safe
                o="${c}"
                ;;
            "/")
                # Keep forward slashes for manifest paths
                o="${c}"
                ;;
            *)
                # Percent-encode everything else
                printf -v o '%%%02X' "'${c}"
                ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Sanitize string for safe use in URLs (legacy function, now uses url_encode)
sanitize_for_url() {
    local input="$1"
    # Truncate to 100 chars first, then URL encode
    local truncated="${input:0:100}"
    url_encode "$truncated"
}

# Validate port number
# Returns: 0 if valid, 1 if invalid (does not exit)
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_message "ERROR" "Invalid port number: $port"
        return 1
    fi
    return 0
}

#######################################################################################
## System Check Functions - Consistent Error Handling
#######################################################################################

# Check if running as root
# Exits with code 1 if not root
rootCheck() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "This script must be run as root. Please use sudo."
        exit 1
    fi
    
    # Only change permissions if already in munki conditions directory
    if [ -f "$0" ] && [[ "$SCRIPT_DIR" == "$MUNKI_CONDITIONS_DIR" ]]; then
        chown root:wheel "$0"
        chmod 700 "$0"  # More restrictive than 755
    fi
}

# Install as munki condition if needed
# Returns: 0 on success, exits with 1 on failure
conditionInstall() {
    if [[ "$SCRIPT_DIR" == "$MUNKI_CONDITIONS_DIR" ]]; then
        log_message "INFO" "Running as munki condition."
        return 0
    else
        log_message "INFO" "Not running as munki condition. Installing to $MUNKI_CONDITIONS_DIR"
        
        # Create directory if it doesn't exist
        if [ ! -d "$MUNKI_CONDITIONS_DIR" ]; then
            if ! mkdir -p "$MUNKI_CONDITIONS_DIR"; then
                log_message "ERROR" "Failed to create conditions directory"
                exit 1
            fi
            chmod 755 "$MUNKI_CONDITIONS_DIR"
        fi
        
        # Copy with secure permissions
        if ! cp "$0" "$MUNKI_CONDITIONS_DIR/"; then
            log_message "ERROR" "Failed to copy script to conditions directory"
            exit 1
        fi
        chmod 700 "$MUNKI_CONDITIONS_DIR/$SCRIPT_NAME"
        chown root:wheel "$MUNKI_CONDITIONS_DIR/$SCRIPT_NAME"
        return 0
    fi
}

#######################################################################################
## Configuration Loading Functions
#######################################################################################

# Get configuration from plist
loadConfiguration() {
    local plist_path="/private/var/root/Library/Preferences/${ENROLL_PLIST}.plist"
    
    if [ -f "$plist_path" ]; then
        log_message "INFO" "Loading configuration from $plist_path"
        
        # Safely read values with error checking
        for var in catalog1 catalog2 catalog3 manifest1 manifest2 manifest3 manifest4; do
            if /usr/bin/defaults read "$ENROLL_PLIST" "$var" >/dev/null 2>&1; then
                value=$(/usr/bin/defaults read "$ENROLL_PLIST" "$var" 2>/dev/null || true)
                # Sanitize the value
                value=$(sanitize_for_url "$value")
                
                case "$var" in
                    catalog1) CATALOG1="$value" ;;
                    catalog2) CATALOG2="$value" ;;
                    catalog3) CATALOG3="$value" ;;
                    manifest1) MANIFEST1="$value" ;;
                    manifest2) MANIFEST2="$value" ;;
                    manifest3) MANIFEST3="$value" ;;
                    manifest4) MANIFEST4="$value" ;;
                esac
            fi
        done
    else
        log_message "WARN" "Configuration plist not found: $plist_path"
    fi
    
    # Build Munki info string for local configuration
    local catalog_list=""
    [ -n "$CATALOG1" ] && catalog_list="${catalog_list}${CATALOG1}"
    [ -n "$CATALOG2" ] && catalog_list="${catalog_list:+,}${CATALOG2}"
    [ -n "$CATALOG3" ] && catalog_list="${catalog_list:+,}${CATALOG3}"
    
    local manifest_list=""
    [ -n "$MANIFEST1" ] && manifest_list="${manifest_list}${MANIFEST1}"
    [ -n "$MANIFEST2" ] && manifest_list="${manifest_list:+,}${MANIFEST2}"
    [ -n "$MANIFEST3" ] && manifest_list="${manifest_list:+,}${MANIFEST3}"
    [ -n "$MANIFEST4" ] && manifest_list="${manifest_list:+,}${MANIFEST4}"
    
    # Log local Munki configuration
    local munki_info="Munki info (local): "
    if [ -n "$catalog_list" ]; then
        munki_info="${munki_info}CATALOGS=${catalog_list}"
    else
        munki_info="${munki_info}CATALOGS=<default>"
    fi
    
    if [ -n "$manifest_list" ]; then
        munki_info="${munki_info}, MANIFESTS=${manifest_list}"
    else
        munki_info="${munki_info}, MANIFESTS=<default>"
    fi
    
    log_message "INFO" "$munki_info"
}

# Get machine-specific variables with validation
# Exits with code 1 if unable to get required info
getMachineInfo() {
    # Call system_profiler ONCE and cache the output
    local hw_info
    hw_info=$(/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null)
    
    if [ -z "$hw_info" ]; then
        log_message "ERROR" "Unable to retrieve hardware information from system_profiler"
        exit 1
    fi
    
    # Extract serial number from cached output
    RECORDNAME=$(echo "$hw_info" | \
                 /usr/bin/awk '/Serial Number/ { print $4; }' | \
                 /usr/bin/grep -E '^[A-Z0-9]+$' || echo "UNKNOWN")
    
    if [ "$RECORDNAME" = "UNKNOWN" ]; then
        log_message "ERROR" "Unable to retrieve valid serial number"
        exit 1
    fi
    
    # Get computer name and sanitize
    DISPLAYNAME=$(/usr/sbin/scutil --get ComputerName 2>/dev/null || echo "Unknown-Computer")
    DISPLAYNAME=$(sanitize_for_url "$DISPLAYNAME")
    
    # Extract UUID from cached output
    UUID=$(echo "$hw_info" | \
           /usr/bin/awk '/Hardware UUID/ { print $3; }' | \
           /usr/bin/grep -E '^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$' || echo "")
    
    if [ -z "$UUID" ]; then
        log_message "ERROR" "Unable to retrieve valid UUID"
        exit 1
    fi
    
    log_message "INFO" "Machine info (local): RECORDNAME=$RECORDNAME, DISPLAYNAME=$DISPLAYNAME, UUID=$UUID"
}

# Get Munki authentication safely
# Exits with code 1 if ManagedInstalls.plist not found
getMunkiAuth() {
    local managed_installs_plist="/var/root/Library/Preferences/ManagedInstalls.plist"
    
    if [ ! -f "$managed_installs_plist" ]; then
        log_message "ERROR" "ManagedInstalls.plist not found"
        exit 1
    fi
    
    # Extract auth header safely 
    AUTH=$(/usr/bin/defaults read "$managed_installs_plist" AdditionalHttpHeaders 2>/dev/null | \
           /usr/bin/grep -o 'Basic [^"]*' | \
           /usr/bin/sed 's/Basic //' | \
           /usr/bin/base64 -D 2>/dev/null || echo "")
    
    if [ -z "$AUTH" ]; then
        log_message "WARN" "No authentication credentials found"
    else
        # Log that we found credentials WITHOUT showing them
        log_message "INFO" "Authentication credentials loaded"
    fi
    
    # Get ManagedInstallDir
    MANAGEDINSTALL_DIR=$(/usr/bin/defaults read /Library/Preferences/ManagedInstalls ManagedInstallDir 2>/dev/null || \
                        echo "/Library/Managed Installs")
    
    # Ensure directory exists
    if [ ! -d "$MANAGEDINSTALL_DIR" ]; then
        log_message "INFO" "Creating $MANAGEDINSTALL_DIR"
        mkdir -p "$MANAGEDINSTALL_DIR"
        chmod 755 "$MANAGEDINSTALL_DIR"
    fi
    
    CONDITIONALITEMS_PLIST="$MANAGEDINSTALL_DIR/ConditionalItems"
}

# Test port connectivity
# Exits with code 1 if connection fails
munkiPortTest() {
    # Extract hostname from URL safely
    SHORT_URL=$(echo "$ENROLL_URL" | /usr/bin/awk -F/ '{print $3}' | /usr/bin/awk -F: '{print $1}')
    
    # Validate hostname
    if [[ ! "$SHORT_URL" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_message "ERROR" "Invalid hostname: $SHORT_URL"
        exit 1
    fi
    
    # Validate port
    if ! validate_port "$PORT"; then
        log_message "ERROR" "Port validation failed for port $PORT"
        exit 1
    fi
    
    # Test connectivity with timeout
    if /usr/bin/nc -z -w5 "$SHORT_URL" "$PORT" >/dev/null 2>&1; then
        log_message "INFO" "$SHORT_URL is reachable on port $PORT"
        /usr/bin/defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-PORT_TEST" -string "200"
    else
        log_message "ERROR" "$SHORT_URL is not reachable on port $PORT"
        /usr/bin/defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-PORT_TEST" -string "404"
        exit 1
    fi
    
    /usr/bin/plutil -convert xml1 "${CONDITIONALITEMS_PLIST}.plist" 2>/dev/null || true
}

#######################################################################################
## JSON Parsing Functions (No Python Required)
#######################################################################################

# Parse JSON response from server using only bash/grep/sed
parse_json() {
    local json="$1"
    local key="$2"
    
    # Use grep and sed to extract the value for a given key
    # This handles simple JSON structure with quoted strings
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Extract JSON message from response
get_json_message() {
    local json="$1"
    # Specifically look for the message field in JSON
    # Handles: "message": "Some message here"
    echo "$json" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

#######################################################################################
## Manifest Management Functions
#######################################################################################

# Check if manifest exists using fetch
# Sets START_ENROLL or START_UPDATE based on result
# Returns: 0 on success (manifest current), sets flags otherwise
manifestTest() {
    # Create temp directory and set up cleanup
    local temp_dir
    temp_dir=$(mktemp -d /tmp/munki-enroll.XXXXXX)
    trap 'rm -rf "$temp_dir"' EXIT
    
    # Build URL with GET parameters
    local fetch_url="${ENROLL_URL}?function=fetch&recordname=${RECORDNAME}&uuid=${UUID}"
    
    # Try to fetch the manifest using recordname and UUID
    local curl_opts=(
        --silent
        --max-time "$MAX_CURL_TIME"
        --write-out "\nHTTP_CODE:%{http_code}"
        --output "$temp_dir/$RECORDNAME.plist"
    )
    
    if [ -n "$AUTH" ]; then
        curl_opts+=(--user "$AUTH")
    fi
    
    # Execute fetch with GET parameters in URL
    set +e
    FETCH_RESPONSE=$(curl "${curl_opts[@]}" "$fetch_url" 2>&1)
    FETCH_EXIT_CODE=$?
    set -e
    
    # Extract HTTP code from response
    HTTP_CODE=$(echo "$FETCH_RESPONSE" | grep "HTTP_CODE:" | sed 's/.*HTTP_CODE://')
    
    log_message "DEBUG" "Fetch HTTP code: $HTTP_CODE"
    
    if [ "$HTTP_CODE" = "200" ] && [ -f "$temp_dir/$RECORDNAME.plist" ]; then
        # Check if it's XML (manifest) or JSON (error)
        if grep -q "<?xml" "$temp_dir/$RECORDNAME.plist" 2>/dev/null; then
            # It's a valid manifest
            log_message "INFO" "Manifest exists and UUID verified for $RECORDNAME"
            
            # Validate plist format
            if /usr/bin/plutil -lint "$temp_dir/$RECORDNAME.plist" >/dev/null 2>&1; then
                MANIFEST_DISPLAYNAME=$(/usr/bin/defaults read "$temp_dir/$RECORDNAME.plist" "display_name" 2>/dev/null || echo "")
                MANIFEST_UUID=$(/usr/bin/defaults read "$temp_dir/$RECORDNAME.plist" "uuid" 2>/dev/null || echo "")
                
                # Extract remote catalogs and manifests
                REMOTE_CATALOGS=$(/usr/bin/defaults read "$temp_dir/$RECORDNAME.plist" "catalogs" 2>/dev/null | grep -v '^(' | grep -v '^)' | sed 's/^[[:space:]]*"//; s/",[[:space:]]*$//; s/"$//' | tr '\n' ',' | sed 's/,$//' || echo "<none>")
                REMOTE_MANIFESTS=$(/usr/bin/defaults read "$temp_dir/$RECORDNAME.plist" "included_manifests" 2>/dev/null | grep -v '^(' | grep -v '^)' | sed 's/^[[:space:]]*"//; s/",[[:space:]]*$//; s/"$//' | tr '\n' ',' | sed 's/,$//' || echo "<none>")
                
                # Clean up any double commas, trim spaces, then format consistently
                REMOTE_CATALOGS=$(echo "$REMOTE_CATALOGS" | sed 's/,,*/,/g; s/^,//; s/,$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/,/, /g')
                REMOTE_MANIFESTS=$(echo "$REMOTE_MANIFESTS" | sed 's/,,*/,/g; s/^,//; s/,$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/,/, /g')
                
                # Log remote info
                log_message "INFO" "Munki info (remote): CATALOGS=${REMOTE_CATALOGS}, MANIFESTS=${REMOTE_MANIFESTS}"
                log_message "INFO" "Machine info (remote): RECORDNAME=$RECORDNAME, DISPLAYNAME=$MANIFEST_DISPLAYNAME, UUID=$MANIFEST_UUID"
                
                if [ "$MANIFEST_DISPLAYNAME" != "$DISPLAYNAME" ]; then
                    log_message "INFO" "Display name changed from '$MANIFEST_DISPLAYNAME' to '$DISPLAYNAME', will update"
                    START_UPDATE=1
                else
                    # Manifest exists and is up to date - checkin was already done by fetch
                    log_message "SUCCESS" "Manifest is up to date (checkin completed via fetch)"
                    exit 0
                fi
            else
                log_message "ERROR" "Invalid manifest plist format"
                exit 1
            fi
        else
            # It's probably a JSON error response
            local json_content=$(cat "$temp_dir/$RECORDNAME.plist")
            local message=$(get_json_message "$json_content")
            log_message "ERROR" "Server returned error: $message"
            exit 1
        fi
    elif [ "$HTTP_CODE" = "404" ]; then
        # Manifest doesn't exist
        log_message "INFO" "Manifest not found (HTTP 404), will enroll"
        START_ENROLL=1
    elif [ "$HTTP_CODE" = "403" ]; then
        # UUID mismatch or auth failure
        log_message "ERROR" "Access forbidden (HTTP 403) - UUID verification failed or authentication error"
        exit 99
    elif [ "$HTTP_CODE" = "400" ]; then
        # Bad request
        log_message "ERROR" "Bad request (HTTP 400) - check script parameters"
        exit 1
    else
        # Some other error
        log_message "ERROR" "Failed to fetch manifest: HTTP code $HTTP_CODE"
        log_message "INFO" "Unable to verify manifest existence, attempting enrollment"
        START_ENROLL=1
    fi
}

# Enroll with the server (using new HTTP codes)
# Exits with appropriate code based on result
munkiEnroll() {
    log_message "INFO" "Starting enrollment process"
    
    # Build curl command with proper escaping
    local curl_opts=(
        --max-time "$MAX_CURL_TIME"
        --get
        --silent
        --write-out "\nHTTP_CODE:%{http_code}"
    )
    
    # URL-encode the parameters to handle all special characters properly
    local data_params=()
    data_params+=("recordname=$(url_encode "$RECORDNAME")")
    data_params+=("displayname=$(url_encode "$DISPLAYNAME")")
    data_params+=("uuid=$UUID")
    
    # Add optional parameters with URL encoding
    [ -n "$CATALOG1" ] && data_params+=("catalog1=$(url_encode "$CATALOG1")")
    [ -n "$CATALOG2" ] && data_params+=("catalog2=$(url_encode "$CATALOG2")")
    [ -n "$CATALOG3" ] && data_params+=("catalog3=$(url_encode "$CATALOG3")")
    [ -n "$MANIFEST1" ] && data_params+=("manifest1=$(url_encode "$MANIFEST1")")
    [ -n "$MANIFEST2" ] && data_params+=("manifest2=$(url_encode "$MANIFEST2")")
    [ -n "$MANIFEST3" ] && data_params+=("manifest3=$(url_encode "$MANIFEST3")")
    [ -n "$MANIFEST4" ] && data_params+=("manifest4=$(url_encode "$MANIFEST4")")
    
    # Add auth if available
    if [ -n "$AUTH" ]; then
        curl_opts+=(--user "$AUTH")
    fi
    
    # Add data parameters to curl
    for param in "${data_params[@]}"; do
        curl_opts+=(-d "$param")
    done
    
    # Execute enrollment
    set +e
    RESPONSE=$(curl "${curl_opts[@]}" "$ENROLL_URL" 2>&1)
    CURL_EXIT_CODE=$?
    set -e
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        log_message "ERROR" "Connection failed with exit code $CURL_EXIT_CODE"
        exit 1
    fi
    
    # Extract HTTP code
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | sed 's/.*HTTP_CODE://')
    JSON_RESPONSE=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
    
    log_message "DEBUG" "Enrollment HTTP code: $HTTP_CODE"
    log_message "DEBUG" "JSON response: $JSON_RESPONSE"
    
    # Parse response based on HTTP code
    case "$HTTP_CODE" in
        201)
            # Created - successful enrollment
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "SUCCESS" "Manifest created for $DISPLAYNAME (serial: $RECORDNAME)"
            log_message "INFO" "Server response: $message"
            exit 0
            ;;
        409)
            # Conflict - manifest already exists
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "INFO" "Manifest already exists for $RECORDNAME"
            log_message "INFO" "Server response: $message"
            exit 0  # Don't treat as error
            ;;
        400)
            # Bad request
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Bad request (HTTP 400): $message"
            exit 1
            ;;
        403)
            # Forbidden
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Access forbidden (HTTP 403): $message"
            exit 1
            ;;
        500)
            # Server error
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Server error (HTTP 500): $message"
            exit 1
            ;;
        *)
            log_message "ERROR" "Unexpected HTTP code: $HTTP_CODE"
            log_message "ERROR" "Response: $JSON_RESPONSE"
            exit 1
            ;;
    esac
}

# Update manifest (using new HTTP codes)
# Exits with appropriate code based on result
munkiUpdate() {
    log_message "INFO" "Updating manifest for $DISPLAYNAME"
    
    # Build curl command with proper escaping
    local curl_opts=(
        --max-time "$MAX_CURL_TIME"
        --get
        --silent
        --write-out "\nHTTP_CODE:%{http_code}"
    )
    
    # URL-encode the parameters
    local data_params=()
    data_params+=("function=update")
    data_params+=("recordname=$(url_encode "$RECORDNAME")")
    data_params+=("displayname=$(url_encode "$DISPLAYNAME")")
    data_params+=("uuid=$UUID")
    
    # Add optional parameters with URL encoding
    [ -n "$CATALOG1" ] && data_params+=("catalog1=$(url_encode "$CATALOG1")")
    [ -n "$CATALOG2" ] && data_params+=("catalog2=$(url_encode "$CATALOG2")")
    [ -n "$CATALOG3" ] && data_params+=("catalog3=$(url_encode "$CATALOG3")")
    [ -n "$MANIFEST1" ] && data_params+=("manifest1=$(url_encode "$MANIFEST1")")
    [ -n "$MANIFEST2" ] && data_params+=("manifest2=$(url_encode "$MANIFEST2")")
    [ -n "$MANIFEST3" ] && data_params+=("manifest3=$(url_encode "$MANIFEST3")")
    [ -n "$MANIFEST4" ] && data_params+=("manifest4=$(url_encode "$MANIFEST4")")
    
    if [ -n "$AUTH" ]; then
        curl_opts+=(--user "$AUTH")
    fi
    
    for param in "${data_params[@]}"; do
        curl_opts+=(-d "$param")
    done
    
    set +e
    RESPONSE=$(curl "${curl_opts[@]}" "$ENROLL_URL" 2>&1)
    CURL_EXIT_CODE=$?
    set -e
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        log_message "ERROR" "Failed to update manifest: exit code $CURL_EXIT_CODE"
        exit 1
    fi
    
    # Extract HTTP code
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | sed 's/.*HTTP_CODE://')
    JSON_RESPONSE=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
    
    log_message "DEBUG" "Update HTTP code: $HTTP_CODE"
    
    # Parse response based on HTTP code
    case "$HTTP_CODE" in
        200)
            # OK - successful update
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "SUCCESS" "Manifest updated for $DISPLAYNAME"
            log_message "INFO" "Server response: $message"
            /usr/bin/defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-update" -string "200"
            /usr/bin/plutil -convert xml1 "${CONDITIONALITEMS_PLIST}.plist" 2>/dev/null || true
            exit 0
            ;;
        404)
            # Not found
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Manifest not found (HTTP 404): $message"
            exit 2
            ;;
        403)
            # Forbidden - UUID mismatch
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Access forbidden (HTTP 403): $message"
            exit 99
            ;;
        400)
            # Bad request
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Bad request (HTTP 400): $message"
            exit 1
            ;;
        500)
            # Server error
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Server error (HTTP 500): $message"
            exit 1
            ;;
        *)
            log_message "ERROR" "Unexpected HTTP code: $HTTP_CODE"
            log_message "ERROR" "Response: $JSON_RESPONSE"
            exit 1
            ;;
    esac
}

# Checkin with server (using new HTTP codes)
# Note: This function is not currently used as fetch performs automatic checkin
# Exits with appropriate code based on result
munkiCheckin() {
    log_message "INFO" "Starting checkin process"
    
    # Build curl command for simple checkin
    local curl_opts=(
        --max-time "$MAX_CURL_TIME"
        --get
        --silent
        --write-out "\nHTTP_CODE:%{http_code}"
    )
    
    local data_params=(
        "function=checkin"
        "recordname=$RECORDNAME"
    )
    
    if [ -n "$AUTH" ]; then
        curl_opts+=(--user "$AUTH")
    fi
    
    for param in "${data_params[@]}"; do
        curl_opts+=(-d "$param")
    done
    
    set +e
    RESPONSE=$(curl "${curl_opts[@]}" "$ENROLL_URL" 2>&1)
    CURL_EXIT_CODE=$?
    set -e
    
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        log_message "ERROR" "Failed to connect to enrollment server for checkin"
        exit 1
    fi
    
    # Extract HTTP code
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | sed 's/.*HTTP_CODE://')
    JSON_RESPONSE=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
    
    log_message "DEBUG" "Checkin HTTP code: $HTTP_CODE"
    
    # Parse response based on HTTP code
    case "$HTTP_CODE" in
        200)
            # OK - successful checkin
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "SUCCESS" "Checkin successful for $RECORDNAME"
            log_message "INFO" "Server response: $message"
            /usr/bin/defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-checkin" -string "200"
            /usr/bin/plutil -convert xml1 "${CONDITIONALITEMS_PLIST}.plist" 2>/dev/null || true
            exit 0
            ;;
        404)
            # Not found
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Manifest not found (HTTP 404): $message"
            exit 2
            ;;
        400)
            # Bad request
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Bad request (HTTP 400): $message"
            exit 1
            ;;
        500)
            # Server error
            local message=$(get_json_message "$JSON_RESPONSE")
            log_message "ERROR" "Server error (HTTP 500): $message"
            exit 1
            ;;
        *)
            log_message "ERROR" "Unexpected HTTP code: $HTTP_CODE"
            log_message "ERROR" "Response: $JSON_RESPONSE"
            exit 1
            ;;
    esac
}

#######################################################################################
## Main Execution
#######################################################################################

# Initialize flags
START_ENROLL=0
START_UPDATE=0

# Create log file with proper permissions
LOG_DIR="$(dirname "$LOG_FILE")"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
fi
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

log_message "INFO" "Starting $SCRIPT_NAME v2.0.0"

# Validate URLs - exit if invalid
if ! validate_url "$REPO_URL" || ! validate_url "$ENROLL_URL"; then
    log_message "ERROR" "URL validation failed - check REPO_URL and ENROLL_URL configuration"
    exit 1
fi

# Run checks and operations in sequence
# Each function will exit with appropriate code if it fails
rootCheck
conditionInstall
loadConfiguration
getMachineInfo
getMunkiAuth
munkiPortTest
manifestTest

# Perform enrollment or update if needed
if [ "$START_ENROLL" -eq 1 ]; then
    munkiEnroll
elif [ "$START_UPDATE" -eq 1 ]; then
    munkiUpdate
else
    # Manifest is up to date - fetch already performed checkin
    log_message "INFO" "No enrollment or update needed - manifest is current"
    exit 0
fi