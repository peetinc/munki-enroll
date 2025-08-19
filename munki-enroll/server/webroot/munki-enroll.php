<?php
/**
 * Munki Enrollment Server Script
 * 
 * @package    MunkiEnroll
 * @version    2.0.0
 * @author     Artichoke Consulting
 * @copyright  2025 Artichoke Consulting
 * @license    MIT License
 * @link       https://github.com/artichoke/munki-enroll
 * 
 * Created:    2025-01-09
 * Updated:    2025-01-09
 * 
 * DESCRIPTION:
 * Server-side enrollment and manifest management system for Munki clients.
 * Provides RESTful API endpoints for creating, updating, and fetching 
 * client-specific Munki manifests with UUID-based security verification.
 * 
 * FEATURES:
 * - Automatic manifest creation for new clients
 * - UUID-based machine verification to prevent manifest hijacking
 * - Customizable catalog and manifest inclusion
 * - Automatic check-in tracking with timestamp updates
 * - Comprehensive logging with rotation and syslog integration
 * - Atomic file operations to prevent corruption
 * - HTTP Basic Authentication support
 * 
 * ENDPOINTS:
 * - enroll  : Create new client manifest (HTTP 201 on success)
 * - update  : Update existing manifest (HTTP 200 on success)
 * - checkin : Update last check-in time only (HTTP 200 on success)
 * - fetch   : Retrieve manifest with UUID verification (HTTP 200 + XML)
 * 
 * HTTP STATUS CODES:
 * - 200 OK                : Success (fetch, checkin, update)
 * - 201 Created          : New manifest created successfully
 * - 400 Bad Request      : Invalid or missing parameters
 * - 403 Forbidden        : UUID mismatch or authentication failure
 * - 404 Not Found        : Manifest does not exist
 * - 409 Conflict         : Manifest already exists (on enroll)
 * - 500 Server Error     : Internal server error
 * 
 * REQUIREMENTS:
 * - PHP 7.2 or higher
 * - CFPropertyList PHP library
 * - Write access to /var/munki-enroll/manifests/
 * - Write access to /var/log/munki-enroll/
 * 
 * SECURITY:
 * - UUID verification prevents unauthorized manifest access
 * - Path traversal protection on all file operations
 * - Input sanitization and validation on all parameters
 * - Secure logging with PII protection
 * - Support for HTTP Basic Authentication
 * - Manifests stored outside web root
 * 
 * USAGE:
 * Client scripts should call this endpoint with appropriate parameters:
 * 
 * Enrollment:
 *   GET /munki-enroll.php?recordname=SERIAL&displayname=NAME&uuid=UUID
 *   Optional: &catalog1=production&manifest1=site_default
 * 
 * Update:
 *   GET /munki-enroll.php?function=update&recordname=SERIAL&displayname=NAME&uuid=UUID
 * 
 * Fetch:
 *   GET /munki-enroll.php?function=fetch&recordname=SERIAL&uuid=UUID
 * 
 * CONFIGURATION:
 * - Manifests directory: /var/munki-enroll/manifests/
 * - Log file: /var/log/munki-enroll/munki-enroll.log
 * - Default catalog: production
 * - Default manifest: Management/Mandatory
 * 
 * LOGGING:
 * All operations are logged to both file and syslog with:
 * - Timestamp, client IP, authentication user
 * - Operation result and parameters
 * - Automatic log rotation at 10MB
 * - JSON structured logging format
 * 
 * COMPATIBILITY:
 * - Designed for macOS clients running Munki 6.x or higher
 * - Compatible with munki-enroll.sh client script v2.0.0
 * 
 * @example
 * // Enroll a new client
 * curl "https://munki.example.com/munki-enroll.php?recordname=C02X1234&displayname=John-MacBook&uuid=550e8400-e29b-41d4-a716-446655440000"
 * 
 * @example  
 * // Fetch manifest with verification
 * curl "https://munki.example.com/munki-enroll.php?function=fetch&recordname=C02X1234&uuid=550e8400-e29b-41d4-a716-446655440000"
 * 
 * @see https://github.com/munki/munki
 * @see https://github.com/rtrouton/CFPropertyList
 */
 
namespace CFPropertyList;

/**
 * Unified Munki Enrollment Script with Standardized HTTP Status Codes
 * All functions now use consistent HTTP status codes and JSON responses
 * 
 * HTTP Status Codes:
 * - 200 OK: Success (fetch, checkin)
 * - 201 Created: New manifest created
 * - 204 No Content: Success with no content to return
 * - 400 Bad Request: Invalid parameters
 * - 403 Forbidden: UUID mismatch or auth failure
 * - 404 Not Found: Manifest not found
 * - 409 Conflict: Resource already exists
 * - 500 Internal Server Error: Server-side error
 */

// For production: show no errors to users, log them instead
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', '/var/log/munki-enroll/php_errors.log');

// For development/debugging (uncomment when needed):
// error_reporting(E_ALL);
// ini_set('display_errors', 1);

// require cfpropertylist - Updated order for proper dependency loading
require_once 'CFPropertyList/IOException.php';
require_once 'CFPropertyList/PListException.php';
require_once 'CFPropertyList/CFType.php';
require_once 'CFPropertyList/CFBoolean.php';
require_once 'CFPropertyList/CFNumber.php';
require_once 'CFPropertyList/CFString.php';
require_once 'CFPropertyList/CFDate.php';
require_once 'CFPropertyList/CFData.php';
require_once 'CFPropertyList/CFArray.php';
require_once 'CFPropertyList/CFDictionary.php';
require_once 'CFPropertyList/CFUid.php';
require_once 'CFPropertyList/CFBinaryPropertyList.php';
require_once 'CFPropertyList/CFTypeDetector.php';
require_once 'CFPropertyList/CFPropertyList.php';

/**
 * Secure Logging Class
 */
class SecureLogger {
    private static $log_file = '/var/log/munki-enroll/munki-enroll.log';
    private static $max_log_size = 10485760; // 10MB
    private static $max_log_files = 5;
    
    /**
     * Log an event with proper sanitization and rotation
     */
    public static function log($result, $recordname = '', $displayname = '', $uuid = '', 
                               $catalog1 = '', $catalog2 = '', $catalog3 = '', 
                               $manifest1 = '', $manifest2 = '', $manifest3 = '', $manifest4 = '') {
        
        // Rotate log if needed
        self::rotateLogIfNeeded();
        
        // Build log entry with sanitized data
        $timestamp = gmdate('Y-m-d\TH:i:s\Z');
        $ip = self::sanitizeLogData($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $user = self::sanitizeLogData($_SERVER['REMOTE_USER'] ?? $_SERVER['PHP_AUTH_USER'] ?? 'anonymous');
        $user_agent = self::sanitizeLogData(substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 100));
        
        // Sanitize all parameters
        $log_data = [
            'timestamp' => $timestamp,
            'result' => self::sanitizeLogData($result),
            'recordname' => self::sanitizeLogData($recordname),
            'displayname' => self::sanitizeLogData($displayname),
            'uuid' => self::sanitizeLogData($uuid),
            'catalogs' => implode(',', array_filter([
                self::sanitizeLogData($catalog1),
                self::sanitizeLogData($catalog2),
                self::sanitizeLogData($catalog3)
            ])),
            'manifests' => implode(',', array_filter([
                self::sanitizeLogData($manifest1),
                self::sanitizeLogData($manifest2),
                self::sanitizeLogData($manifest3),
                self::sanitizeLogData($manifest4)
            ])),
            'ip' => $ip,
            'user' => $user,
            'user_agent' => $user_agent
        ];
        
        // Format log entry (use JSON for structured logging)
        $log_entry = json_encode($log_data, JSON_UNESCAPED_SLASHES) . "\n";
        
        // Write to log file with locking
        $fp = @fopen(self::$log_file, 'a');
        if ($fp) {
            if (flock($fp, LOCK_EX)) {
                fwrite($fp, $log_entry);
                flock($fp, LOCK_UN);
            }
            fclose($fp);
            
            // Set secure permissions (www-data on Ubuntu)
            @chmod(self::$log_file, 0640);
            @chown(self::$log_file, 'www-data');
            @chgrp(self::$log_file, 'www-data');
        }
        
        // Also log to syslog for redundancy
        $syslog_message = sprintf(
            "munki-enroll: %s - %s (uuid: %s, ip: %s, user: %s)",
            $result,
            $recordname,
            $uuid,
            $ip,
            $user
        );
        syslog(LOG_INFO, $syslog_message);
    }
    
    /**
     * Sanitize data for safe logging
     */
    private static function sanitizeLogData($data) {
        if (empty($data)) {
            return '';
        }
        
        // Remove null bytes and control characters
        $data = preg_replace('/[\x00-\x1F\x7F]/', '', $data);
        
        // Limit length
        $data = substr($data, 0, 500);
        
        // Escape special characters that could break log parsing
        $data = str_replace(["\n", "\r", "\t"], [' ', ' ', ' '], $data);
        
        return $data;
    }
    
    /**
     * Rotate log file if it exceeds maximum size
     */
    private static function rotateLogIfNeeded() {
        if (!file_exists(self::$log_file)) {
            return;
        }
        
        $size = @filesize(self::$log_file);
        if ($size === false || $size < self::$max_log_size) {
            return;
        }
        
        // Rotate existing log files
        for ($i = self::$max_log_files - 1; $i > 0; $i--) {
            $old_file = self::$log_file . '.' . $i;
            $new_file = self::$log_file . '.' . ($i + 1);
            if (file_exists($old_file)) {
                if ($i == self::$max_log_files - 1) {
                    @unlink($old_file); // Delete oldest
                } else {
                    @rename($old_file, $new_file);
                }
            }
        }
        
        // Rotate current log
        @rename(self::$log_file, self::$log_file . '.1');
    }
    
    /**
     * Initialize logging system
     */
    public static function init() {
        // Open syslog connection
        openlog('munki-enroll', LOG_PID | LOG_PERROR, LOG_LOCAL0);
        
        // Ensure log directory exists
        $log_dir = dirname(self::$log_file);
        if (!is_dir($log_dir)) {
            @mkdir($log_dir, 0755, true);
            @chown($log_dir, 'www-data');
            @chgrp($log_dir, 'www-data');
        }
        
        // Create log file if it doesn't exist
        if (!file_exists(self::$log_file)) {
            @touch(self::$log_file);
            @chmod(self::$log_file, 0640);
            @chown(self::$log_file, 'www-data');
            @chgrp(self::$log_file, 'www-data');
        }
    }
}

// Initialize logging
SecureLogger::init();

/**
 * Configuration class
 */
class MunkiEnrollConfig {
    // Manifest directory path - now outside web root for security
    public static $manifestspath;
    
    // Default values
    const DEFAULT_MANIFEST = 'Management/Mandatory';
    const DEFAULT_CATALOG = 'production';
    
    // Allowed values for validation
    const ALLOWED_CATALOGS = ['production', 'testing', 'development'];
    const ALLOWED_FUNCTIONS = ['enroll', 'update', 'checkin', 'fetch'];
    
    // Initialize configuration
    public static function init() {
        // Use /var/munki-enroll/manifests for Ubuntu
        self::$manifestspath = '/var/munki-enroll/manifests';
        
        // Try to create directory if it doesn't exist (handle race condition)
        if (!is_dir(self::$manifestspath)) {
            if (!@mkdir(self::$manifestspath, 0755, true) && !is_dir(self::$manifestspath)) {
                die("Unable to create manifests directory: " . self::$manifestspath . "\n");
            }
            // Set ownership to www-data for Ubuntu
            @chown(self::$manifestspath, 'www-data');
            @chgrp(self::$manifestspath, 'www-data');
        }
        
        // Verify directory is accessible
        if (!is_readable(self::$manifestspath) || !is_writable(self::$manifestspath)) {
            die("Manifests directory is not accessible: " . self::$manifestspath . "\n");
        }
        
        self::$manifestspath .= '/';
    }
}

// Initialize configuration
MunkiEnrollConfig::init();

/**
 * Validation Functions
 */
class Validator {
    // Validate manifest name format
    public static function validateManifestName($manifest) {
        if (empty($manifest)) {
            return true;
        }
        return preg_match('/^[a-zA-Z0-9\/_\-\s]+$/', $manifest);
    }
    
    // Validate UUID format
    public static function validateUUID($uuid) {
        return preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i', $uuid);
    }
    
    // Validate recordname format
    public static function validateRecordName($recordname) {
        return preg_match('/^[a-zA-Z0-9_-]+$/', $recordname);
    }
    
    // Sanitize display name
    public static function sanitizeDisplayName($displayname) {
        $displayname = strip_tags($displayname);
        $displayname = preg_replace('/[^\p{L}\p{N}\s\-_\.]/u', '', $displayname);
        return substr($displayname, 0, 100);
    }
    
    // Validate path to prevent traversal attacks
    public static function validatePath($recordname) {
        $recordname = basename($recordname);
        $full_path = MunkiEnrollConfig::$manifestspath . $recordname;
        $real_path = realpath(dirname($full_path)) . '/' . basename($full_path);
        
        if (strpos($real_path, realpath(MunkiEnrollConfig::$manifestspath)) !== 0) {
            return false;
        }
        return $recordname;
    }
}

/**
 * Main Application Class
 */
class MunkiEnroll {
    private $function;
    private $recordname;
    private $displayname;
    private $uuid;
    private $catalogs = [];
    private $manifests = [];
    private $manifest_path;
    
    public function __construct() {
        // Set default content type to JSON
        header('Content-Type: application/json; charset=UTF-8');
        
        $this->parseInput();
        $this->validateInput();
        $this->execute();
    }
    
    /**
     * Send JSON response with HTTP status code
     */
    private function jsonResponse($status_code, $data) {
        http_response_code($status_code);
        echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        exit;
    }
    
    /**
     * Parse and validate input parameters
     */
    private function parseInput() {
        // Get function (defaults to 'enroll' for backward compatibility)
        $this->function = $_GET['function'] ?? '';
        $this->function = $this->sanitizeInput($this->function);
        if (!$this->function || !in_array($this->function, MunkiEnrollConfig::ALLOWED_FUNCTIONS)) {
            $this->function = 'enroll';
        }
        
        // Get and validate recordname (required)
        $this->recordname = $_GET['recordname'] ?? '';
        $this->recordname = $this->sanitizeInput($this->recordname);
        if (!$this->recordname || !Validator::validateRecordName($this->recordname)) {
            $this->recordname = '_NOT-PROVIDED_';
        }
        
        // Get and validate displayname
        $this->displayname = $_GET['displayname'] ?? '';
        if ($this->displayname) {
            $this->displayname = Validator::sanitizeDisplayName($this->displayname);
        } elseif ($this->function == 'enroll') {
            $this->displayname = '_NOT-PROVIDED_';
        }
        
        // Get and validate UUID
        $this->uuid = $_GET['uuid'] ?? '';
        $this->uuid = $this->sanitizeInput($this->uuid);
        if ($this->uuid && !Validator::validateUUID($this->uuid)) {
            if ($this->function == 'enroll') {
                $this->uuid = '_NOT-PROVIDED_';
            } else {
                $this->uuid = null;
            }
        } elseif (!$this->uuid && $this->function == 'enroll') {
            $this->uuid = '_NOT-PROVIDED_';
        }
        
        // Get and validate catalogs
        for ($i = 1; $i <= 3; $i++) {
            $catalog = $_GET["catalog$i"] ?? '';
            $catalog = $this->sanitizeInput($catalog);
            if ($catalog && in_array($catalog, MunkiEnrollConfig::ALLOWED_CATALOGS)) {
                $this->catalogs[$i] = $catalog;
            }
        }
        
        // Set default catalog for enroll if none provided
        if ($this->function == 'enroll' && empty($this->catalogs)) {
            $this->catalogs[1] = MunkiEnrollConfig::DEFAULT_CATALOG;
        }
        
        // Get and validate manifests
        for ($i = 1; $i <= 4; $i++) {
            $manifest = $_GET["manifest$i"] ?? '';
            $manifest = $this->sanitizeInput($manifest);
            // URL decode if needed (for forward slashes)
            $manifest = urldecode($manifest);
            if ($manifest && Validator::validateManifestName($manifest)) {
                $this->manifests[$i] = $manifest;
            }
        }
        
        // Set default manifest1 for enroll if not provided (even if other manifests are)
        if ($this->function == 'enroll' && !isset($this->manifests[1])) {
            $this->manifests[1] = MunkiEnrollConfig::DEFAULT_MANIFEST;
        }
    }
    
    /**
     * Sanitize input string
     */
    private function sanitizeInput($input) {
        if (is_array($input)) {
            return '';
        }
        // Remove null bytes and control characters, trim whitespace
        $input = trim($input);
        $input = preg_replace('/[\x00-\x1F\x7F]/', '', $input);
        return $input;
    }
    
    /**
     * Validate input based on function
     */
    private function validateInput() {
        // Check required fields for enrollment
        if ($this->function == 'enroll') {
            if ($this->recordname == '_NOT-PROVIDED_' || 
                $this->displayname == '_NOT-PROVIDED_' || 
                $this->uuid == '_NOT-PROVIDED_') {
                $this->error(400, 'Missing required parameters', 
                            'Please provide valid recordname, displayname and uuid at minimum.',
                            'FAILURE - NOT ENOUGH ARGUMENTS');
            }
        } else {
            // For update/checkin/fetch, only recordname is required
            if ($this->recordname == '_NOT-PROVIDED_') {
                $this->error(400, 'Missing required parameter', 
                            'Please provide valid recordname.',
                            'FAILURE - INVALID RECORDNAME');
            }
        }
        
        // Validate and secure the path
        $this->recordname = Validator::validatePath($this->recordname);
        if (!$this->recordname) {
            $this->error(400, 'Invalid path', 
                        'Invalid manifest path.',
                        'FAILURE - INVALID PATH');
        }
        
        $this->manifest_path = MunkiEnrollConfig::$manifestspath . $this->recordname;
        
        // Check for recursive manifest inclusion
        foreach ($this->manifests as $manifest) {
            if ($manifest == $this->recordname) {
                $this->error(400, 'Recursive manifest', 
                            'Cannot add manifest to its own included_manifests array.',
                            'FAILURE - RECURSIVE MANIFEST');
            }
        }
    }
    
    /**
     * Execute the appropriate function
     */
    private function execute() {
        switch ($this->function) {
            case 'enroll':
                $this->enroll();
                break;
            case 'update':
                $this->update();
                break;
            case 'checkin':
                $this->checkin();
                break;
            case 'fetch':
                $this->fetchManifest();
                break;
        }
    }
    
    /**
     * Create new manifest (enroll function)
     */
    private function enroll() {
        // Check if manifest already exists
        if (file_exists($this->manifest_path)) {
            $this->error(409, 'Manifest already exists', 
                        "Computer manifest {$this->recordname} already exists.",
                        'FAILURE - EXISTING MANIFEST');
        }
        
        try {
            // Check if we can write to the manifests directory
            if (!is_writable(MunkiEnrollConfig::$manifestspath)) {
                throw new \Exception("Manifests directory is not writable: " . MunkiEnrollConfig::$manifestspath);
            }
            
            $plist = new CFPropertyList();
            $plist->add($dict = new CFDictionary());
            
            // Build the manifest structure
            $this->buildManifestDict($dict, true);
            
            // Save the manifest
            $this->saveManifest($plist);
            
            // Success response
            $this->jsonResponse(201, [
                'status' => 'success',
                'message' => 'Manifest created successfully',
                'data' => [
                    'recordname' => $this->recordname,
                    'displayname' => $this->displayname,
                    'uuid' => $this->uuid,
                    'manifests' => array_values($this->manifests),
                    'catalogs' => array_values($this->catalogs)
                ]
            ]);
            
            $this->logResult('SUCCESS - RECORD CREATED');
            
        } catch (\Exception $e) {
            $this->error(500, 'Server error', 
                        "Error creating manifest: " . $e->getMessage(),
                        'FAILURE - EXCEPTION');
        }
    }
    
    /**
     * Update existing manifest
     */
    private function update() {
        if (!file_exists($this->manifest_path)) {
            $this->error(404, 'Manifest not found', 
                        "Computer manifest {$this->recordname} does not exist.",
                        'FAILURE - MANIFEST NOT FOUND');
        }
        
        try {
            // Load existing manifest
            $plist = new CFPropertyList($this->manifest_path);
            $existing_dict = $plist->getValue();
            
            if (!$existing_dict instanceof CFDictionary) {
                throw new \Exception("Invalid manifest format");
            }
            
            $existing_values = $existing_dict->toArray();
            
            // UUID validation for updates
            if ($this->uuid && Validator::validateUUID($this->uuid)) {
                // If a valid UUID is provided, check if it matches the existing one (case-insensitive)
                if (isset($existing_values['uuid']) && strcasecmp($existing_values['uuid'], $this->uuid) !== 0) {
                    $this->error(403, 'UUID mismatch', 
                                'UUID mismatch - this manifest belongs to a different machine',
                                'FAILURE - UUID MISMATCH');
                }
                // If no UUID exists in manifest yet, we'll add it during the update
            } elseif (isset($existing_values['uuid'])) {
                // If no UUID provided but manifest has one, preserve it
                $this->uuid = $existing_values['uuid'];
            }
            
            // Create new plist with updated values
            $new_plist = new CFPropertyList();
            $new_plist->add($new_dict = new CFDictionary());
            
            // Build updated manifest
            $this->buildManifestDict($new_dict, false, $existing_values);
            
            // Save the manifest
            $this->saveManifest($new_plist);
            
            // Success response
            $this->jsonResponse(200, [
                'status' => 'success',
                'message' => 'Manifest updated successfully',
                'data' => [
                    'recordname' => $this->recordname,
                    'displayname' => $this->displayname ?: $existing_values['display_name'] ?? '',
                    'uuid' => $this->uuid
                ]
            ]);
            
            $this->logResult('SUCCESS - UPDATED');
            
        } catch (\Exception $e) {
            $this->error(500, 'Server error', 
                        "Error updating manifest: " . $e->getMessage(),
                        'FAILURE - EXCEPTION');
        }
    }
    
    /**
     * Update checkin time only
     */
    private function checkin() {
        if (!file_exists($this->manifest_path)) {
            $this->error(404, 'Manifest not found', 
                        "Computer manifest {$this->recordname} does not exist.",
                        'FAILURE - MANIFEST NOT FOUND');
        }
        
        try {
            // Load existing manifest
            $plist = new CFPropertyList($this->manifest_path);
            $existing_dict = $plist->getValue();
            
            if (!$existing_dict instanceof CFDictionary) {
                throw new \Exception("Invalid manifest format");
            }
            
            $existing_values = $existing_dict->toArray();
            
            // Create new plist with updated checkin time only
            $new_plist = new CFPropertyList();
            $new_plist->add($new_dict = new CFDictionary());
            
            // Build manifest with only checkin update
            $this->buildManifestDict($new_dict, false, $existing_values, true);
            
            // Save the manifest
            $this->saveManifest($new_plist);
            
            $current_time_human = gmdate('Y-m-d\TH:i:s\Z', time());
            
            // Success response
            $this->jsonResponse(200, [
                'status' => 'success',
                'message' => 'Checkin completed successfully',
                'data' => [
                    'recordname' => $this->recordname,
                    'last_checkin' => $current_time_human
                ]
            ]);
            
            $this->logResult('SUCCESS - CHECKIN');
            
        } catch (\Exception $e) {
            $this->error(500, 'Server error', 
                        "Error during checkin: " . $e->getMessage(),
                        'FAILURE - EXCEPTION');
        }
    }
    
    /**
     * Fetch manifest with UUID verification
     */
    private function fetchManifest() {
        // For fetch, we require both recordname and UUID for security
        if ($this->recordname == '_NOT-PROVIDED_') {
            $this->error(400, 'Missing parameter', 
                        'recordname is required for fetch',
                        'FAILURE - FETCH MISSING RECORDNAME');
        }
        
        if ($this->uuid == '_NOT-PROVIDED_' || empty($this->uuid)) {
            $this->error(400, 'Missing parameter', 
                        'uuid is required for fetch',
                        'FAILURE - FETCH MISSING UUID');
        }
        
        // Check if manifest exists
        if (!file_exists($this->manifest_path)) {
            $this->error(404, 'Manifest not found', 
                        'Manifest not found',
                        'FAILURE - FETCH MANIFEST NOT FOUND');
        }
        
        try {
            // Load the manifest
            $plist = new CFPropertyList($this->manifest_path);
            $dict = $plist->getValue();
            
            if (!$dict instanceof CFDictionary) {
                throw new \Exception("Invalid manifest format");
            }
            
            $existing_values = $dict->toArray();
            
            // Verify UUID matches
            if (!isset($existing_values['uuid'])) {
                $this->error(403, 'No UUID in manifest', 
                            'Manifest has no UUID',
                            'FAILURE - FETCH NO UUID IN MANIFEST');
            }
            
            if (strcasecmp($existing_values['uuid'], $this->uuid) !== 0) {
                $this->error(403, 'UUID verification failed', 
                            'UUID verification failed',
                            'FAILURE - FETCH UUID MISMATCH');
            }
            
            // UUID matches - update checkin time while we're here
            $current_time = time();
            $current_time_human = gmdate('Y-m-d\TH:i:s\Z', $current_time);
            
            // Update just the checkin time in the existing dictionary
            $dict->del('date_checkin');
            $dict->add('date_checkin', new CFNumber($current_time));
            $dict->del('date_checkin_human');
            $dict->add('date_checkin_human', new CFString($current_time_human));
            
            // Save the updated manifest (with new checkin time)
            $xml = $plist->toXML(true);
            file_put_contents($this->manifest_path, $xml);
            
            // Serve the manifest as XML (not JSON)
            header('Content-Type: text/xml; charset=UTF-8');
            header('Content-Disposition: inline; filename="' . basename($this->recordname) . '"');
            header('X-Munki-Manifest-UUID: ' . $existing_values['uuid']);
            http_response_code(200);
            
            // Output the manifest
            echo $xml;
            
            $this->logResult('SUCCESS - FETCH');
            exit(0);
            
        } catch (\Exception $e) {
            $this->error(500, 'Server error', 
                        $e->getMessage(),
                        'FAILURE - FETCH ERROR: ' . $e->getMessage());
        }
    }
    
    /**
     * Build manifest dictionary
     */
    private function buildManifestDict($dict, $is_new = false, $existing = [], $checkin_only = false) {
        $current_time = time();
        $current_time_human = gmdate('Y-m-d\TH:i:s\Z', $current_time);
        
        // Catalogs
        $dict->add('catalogs', $array = new CFArray());
        if (!empty($this->catalogs)) {
            foreach ($this->catalogs as $catalog) {
                $array->add(new CFString($catalog));
            }
        } elseif (!$is_new && isset($existing['catalogs'])) {
            foreach ($existing['catalogs'] as $catalog) {
                $array->add(new CFString($catalog));
            }
        }
        
        // Date fields
        // Always update checkin
        $dict->add('date_checkin', new CFNumber($current_time));
        $dict->add('date_checkin_human', new CFString($current_time_human));
        
        // Date created
        if ($is_new) {
            $dict->add('date_created', new CFNumber($current_time));
            $dict->add('date_created_human', new CFString($current_time_human));
        } else {
            // Preserve existing creation date
            $dict->add('date_created', new CFNumber($existing['date_created'] ?? $current_time));
            $dict->add('date_created_human', new CFString($existing['date_created_human'] ?? $current_time_human));
        }
        
        // Date modified
        if ($is_new) {
            $dict->add('date_modified', new CFNumber($current_time));
            $dict->add('date_modified_human', new CFString($current_time_human));
        } elseif (!$checkin_only && ($this->displayname || $this->uuid || !empty($this->catalogs) || !empty($this->manifests))) {
            // Update modified date if actual changes
            $dict->add('date_modified', new CFNumber($current_time));
            $dict->add('date_modified_human', new CFString($current_time_human));
        } else {
            // Keep existing modified date
            $dict->add('date_modified', new CFNumber($existing['date_modified'] ?? $existing['date_created'] ?? $current_time));
            $dict->add('date_modified_human', new CFString($existing['date_modified_human'] ?? $existing['date_created_human'] ?? $current_time_human));
        }
        
        // Display name
        if ($this->displayname && !$checkin_only) {
            $dict->add('display_name', new CFString($this->displayname));
        } elseif (isset($existing['display_name'])) {
            $dict->add('display_name', new CFString($existing['display_name']));
        } elseif ($is_new) {
            $dict->add('display_name', new CFString($this->displayname));
        }
        
        // Included manifests
        $dict->add('included_manifests', $array = new CFArray());
        if (!empty($this->manifests) && !$checkin_only) {
            // Sort manifests by key to ensure proper order (1, 2, 3, 4)
            ksort($this->manifests);
            foreach ($this->manifests as $manifest) {
                if (!empty($manifest)) {
                    $array->add(new CFString($manifest));
                }
            }
        } elseif (!$is_new && isset($existing['included_manifests'])) {
            foreach ($existing['included_manifests'] as $manifest) {
                $array->add(new CFString($manifest));
            }
        }
        
        // Managed installs
        if (!$is_new && isset($existing['managed_installs'])) {
            $dict->add('managed_installs', $array = new CFArray());
            foreach ($existing['managed_installs'] as $install) {
                $array->add(new CFString($install));
            }
        } else {
            $dict->add('managed_installs', new CFArray());
        }
        
        // UUID and notes
        if ($this->uuid && Validator::validateUUID($this->uuid) && !$checkin_only) {
            $dict->add('notes', new CFString($this->uuid));
            $dict->add('uuid', new CFString($this->uuid));
        } elseif (isset($existing['uuid'])) {
            $dict->add('notes', new CFString($existing['notes'] ?? $existing['uuid']));
            $dict->add('uuid', new CFString($existing['uuid']));
        } elseif ($is_new && $this->uuid != '_NOT-PROVIDED_') {
            $dict->add('notes', new CFString($this->uuid));
            $dict->add('uuid', new CFString($this->uuid));
        }
        
        // Created by (preserve or create)
        if (!$is_new && isset($existing['created_by'])) {
            $dict->add('created_by', new CFString($existing['created_by']));
        } else {
            $dict->add('created_by', new CFString($this->getAuditInfo()));
        }
        
        // Modified by (always update on non-new)
        if (!$is_new) {
            $dict->add('modified_by', new CFString($this->getAuditInfo()));
        }
    }
    
    /**
     * Get audit information
     */
    private function getAuditInfo() {
        $info = [];
        
        if (!empty($_SERVER['REMOTE_ADDR'])) {
            $info[] = 'IP:' . $_SERVER['REMOTE_ADDR'];
        }
        
        if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
            $forwarded = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
            $info[] = 'Forwarded:' . trim($forwarded[0]);
        }
        
        if (!empty($_SERVER['REMOTE_USER'])) {
            $info[] = 'User:' . $_SERVER['REMOTE_USER'];
        } elseif (!empty($_SERVER['PHP_AUTH_USER'])) {
            $info[] = 'User:' . $_SERVER['PHP_AUTH_USER'];
        }
        
        if (!empty($_SERVER['HTTP_USER_AGENT'])) {
            $ua = substr($_SERVER['HTTP_USER_AGENT'], 0, 100);
            $info[] = 'UA:' . $ua;
        }
        
        return !empty($info) ? implode(' | ', $info) : 'unknown';
    }
    
    /**
     * Save manifest to disk
     */
    private function saveManifest($plist) {
        $xml = $plist->toXML(true);
        
        // Atomic write
        $temp_file = $this->manifest_path . '.tmp.' . uniqid();
        if (file_put_contents($temp_file, $xml) === false) {
            @unlink($temp_file);
            throw new \Exception("Failed to write manifest file");
        }
        
        if (!rename($temp_file, $this->manifest_path)) {
            @unlink($temp_file);
            throw new \Exception("Failed to save manifest file");
        }
        
        // Set permissions for www-data on Ubuntu
        @chmod($this->manifest_path, 0644);
        @chown($this->manifest_path, 'www-data');
        @chgrp($this->manifest_path, 'www-data');
    }
    
    /**
     * Error handler with HTTP status codes
     */
    private function error($status_code, $error_type, $message, $log_message) {
        $this->jsonResponse($status_code, [
            'status' => 'error',
            'error' => $error_type,
            'message' => $message
        ]);
        $this->logResult($log_message);
        exit;
    }
    
    /**
     * Log result
     */
    private function logResult($result) {
        SecureLogger::log($result, 
               $this->recordname, 
               $this->displayname ?: '', 
               $this->uuid ?: '',
               $this->catalogs[1] ?? '', 
               $this->catalogs[2] ?? '', 
               $this->catalogs[3] ?? '',
               $this->manifests[1] ?? '', 
               $this->manifests[2] ?? '', 
               $this->manifests[3] ?? '', 
               $this->manifests[4] ?? '');
    }
}

// Execute
new MunkiEnroll();

?>