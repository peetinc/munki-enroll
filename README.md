# munki-enroll v2.0.0
A modernized, secure, and robust Munki enrollment system with UUID-based manifest verification.

## Overview

Munki Enroll v2.0.0 is a complete rewrite of the enrollment system, providing automatic client enrollment in Munki with enhanced security, standardized HTTP status codes, and comprehensive error handling. This version represents a significant evolution from the original concept by Cody Eding (2012), incorporating modern best practices and security standards.

**Key improvements in v2.0.0:**
- 🔒 UUID-based manifest verification prevents unauthorized access
- 🌐 RESTful API with standardized HTTP status codes
- 📊 Comprehensive logging with rotation and syslog integration
- 🔄 Automatic check-in tracking with fetch operations
- ⚡ Atomic file operations prevent corruption
- 🛡️ Enhanced security with path traversal protection
- 📝 JSON responses for better API integration

*This version was developed by Artichoke Consulting with assistance from Claude Opus 4.1, ensuring modern coding standards and security best practices.*

## Essential Reading

Before implementing any Munki enrollment system, please read:
- [An opinionated guide to Munki manifests](https://groob.io/posts/manifest-guide/)
- [Another opinionated guide to Munki manifests](http://technology.siprep.org/another-opinionated-guide-to-munki-manifests/)

## System Requirements

### Server Requirements
- PHP 7.2 or higher
- Web server (Apache/Nginx) with PHP support
- [TECLIB/CFPropertyList](https://github.com/TECLIB/CFPropertyList) library
- Write access to manifest and log directories
- Ubuntu/Debian recommended (also supports RHEL/CentOS/macOS)

### Client Requirements
- macOS 10.12 or later
- Munki 5.x or higher
- Root access for enrollment script execution

## Usage

### Initial Enrollment

Deploy the script to client machines and run:
```bash
sudo /path/to/munki-enroll.sh
```

The script will:
1. Verify connectivity to the enrollment server
2. Gather machine information (serial, UUID, computer name)
3. Create or update the manifest on the server
4. Install itself as a Munki condition for ongoing updates

### Automatic Features

- **Auto-installation**: Script copies itself to `/usr/local/munki/conditions/` if not already there
- **Display name updates**: Automatically updates when computer name changes
- **Check-in tracking**: Records last check-in time with every fetch operation
- **UUID verification**: Prevents manifest hijacking between machines

## API Endpoints

### Enrollment (Default)
```bash
GET /munki-enroll.php?recordname=SERIAL&displayname=NAME&uuid=UUID
Optional: &catalog1=production&manifest1=site_default
```
**Returns:** HTTP 201 (Created) or 409 (Already Exists)

### Update
```bash
GET /munki-enroll.php?function=update&recordname=SERIAL&displayname=NAME&uuid=UUID
```
**Returns:** HTTP 200 (Success) or 403 (UUID Mismatch)

### Fetch
```bash
GET /munki-enroll.php?function=fetch&recordname=SERIAL&uuid=UUID
```
**Returns:** HTTP 200 + XML manifest or 403 (UUID Mismatch)

### Check-in
```bash
GET /munki-enroll.php?function=checkin&recordname=SERIAL
```
**Returns:** HTTP 200 (Success)

## HTTP Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Successful update, fetch, or check-in |
| 201 | Created | New manifest created successfully |
| 400 | Bad Request | Missing or invalid parameters |
| 403 | Forbidden | UUID mismatch or authentication failure |
| 404 | Not Found | Manifest does not exist |
| 409 | Conflict | Manifest already exists (on enrollment) |
| 500 | Server Error | Internal server error |

## Exit Codes (Client Script)

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Operation completed successfully |
| 1 | General Error | Connection, validation, or unexpected issues |
| 2 | Not Found | Manifest not found on server (404) |
| 99 | UUID Mismatch | Security violation - manifest locked to different device |

## Security Features

### UUID Verification
Each manifest is locked to a specific hardware UUID, preventing:
- Manifest hijacking between devices
- Unauthorized access to other machines' configurations
- Accidental cross-contamination of settings

### Path Traversal Protection
All file operations validate paths to prevent directory traversal attacks.

### Input Sanitization
- Display names limited to 100 characters
- Special characters filtered
- SQL injection prevention (no database used)
- XSS protection on all inputs

### Secure Logging
- Automatic log rotation at 10MB
- JSON structured logging
- PII protection and sanitization
- Dual logging to file and syslog

## Logging

### Server Logs
- **Location**: `/var/log/munki-enroll/munki-enroll.log`
- **Format**: JSON structured logging
- **Rotation**: Automatic at 10MB, keeps 5 versions
- **Syslog**: Also logs to syslog facility LOCAL0

### Client Logs
- **Location**: `/var/log/munki-enroll/munki-enroll.log`
- **Verbosity**: Configurable (0=quiet, 1=normal, 2=debug)
- **Rotation**: Automatic at 10MB, keeps 5 versions

### Log Entry Example
```json
{
    "timestamp": "2025-01-09T12:00:00Z",
    "result": "SUCCESS - RECORD CREATED",
    "recordname": "C02ABC123DEF",
    "displayname": "John-MacBook-Pro",
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "catalogs": "production",
    "manifests": "Management/Mandatory,Site/Building-A",
    "ip": "192.168.1.100",
    "user": "munki",
    "user_agent": "curl/7.64.1"
}
```

## Troubleshooting

### Common Issues

**403 Forbidden - UUID Mismatch**
- Cause: Manifest is locked to a different machine
- Solution: Delete the existing manifest or contact administrator

**404 Not Found**
- Cause: Manifest doesn't exist on server
- Solution: Run enrollment to create manifest

**Connection Failed**
- Check network connectivity
- Verify REPO_URL and PORT settings
- Check firewall rules
- Verify SSL certificates

### Debug Mode

Enable debug logging in the client script:
```bash
VERBOSITY_LEVEL=2  # Line 67 in munki-enroll.sh
```

Enable debug mode in PHP (development only):
```php
// Uncomment lines 24-25 in munki-enroll.php
error_reporting(E_ALL);
ini_set('display_errors', 1);
```

### Verify Installation

Test the API directly:
```bash
# Test connectivity
curl -I https://munki.yourdomain.com/repo/munki-enroll/munki-enroll.php

# Test enrollment (will fail without valid parameters)
curl "https://munki.yourdomain.com/repo/munki-enroll/munki-enroll.php?recordname=TEST&displayname=Test&uuid=test-uuid"
```

## License

Munki Enroll v2.0.0, like the contained CFPropertyList project, is published under the [MIT License](http://www.opensource.org/licenses/mit-license.php).

Original concept Copyright (c) 2012 Cody Eding  
This version Copyright (c) 2025 Artichoke Consulting

## Acknowledgments

- Original [munki-enroll](https://github.com/edingc/munki-enroll) concept by Cody Eding
- [TECLIB/CFPropertyList](https://github.com/TECLIB/CFPropertyList) for plist handling
- The Munki community for ongoing feedback and support
- Claude Opus 4.1 for development assistance and code review

## Version History

### v2.0.0 (2025-01-09)
- Complete rewrite with modern security standards
- UUID-based manifest verification
- Standardized HTTP status codes
- JSON API responses
- Comprehensive logging system
- Atomic file operations
- Auto check-in with fetch
- Enhanced error handling

### v1.x (Legacy)
- Original fork with basic enrollment
- Display name updates
- Conditional item support