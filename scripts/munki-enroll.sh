#!/bin/bash 

##### This version of the script assumes you have an https-enabled Munki server with basic authentication
##### If you do not change the ENROLL_URL and PORT as needed. Also remove (don't comment out) "-u "$AUTH" \" 
##### Change ENROLL_URL's variable value to your actual URL
##### This script must be run as root to access $ENROLL_PLIST and /var/root/Library/Preferences/ManagedInstalls.plist

#######################
## User-set variables
# Change this URL to the location fo your Munki Enroll install
# if using non-standard port enter https://munki.domain:8443/repo/munki-enroll/enroll.php as well as defining PORT=8443
REPO_URL="https://munki.domain/repo"
ENROLL_URL="$REPO_URL/munki-enroll/enroll.php"
UPDATE_URL="$REPO_URL/munki-enroll/update.php"
PORT=443
#Catalogs and Manifests - Hard code these variables or write them into /private/var/root/Library/$ENROLL_PLIST.plist
#Values set in $ENROLL_PLIST override values set here. However, if CATALOG2 is defined here, not a key in $ENROLL_PLIST.plist the value defined below will be used
ENROLL_PLIST="domain.munki.munki-enroll"
#Default Catalog (CATALOG1) is defined in enroll.php. Define here only to override default of "production"
CATALOG1=
CATALOG2=
CATALOG2=
#Default Manifest (MANIFEST1) is defined in enroll.php. Define here only to override default of "YOUR/DEFAULT/MANIFEST"
MANIFEST1=
MANIFEST2=
MANIFEST3=
MANIFEST4=
#######################
#######################
## Runtime variables
# folder containging script
SCRIPT_FOLDER=`dirname "$0"`
# Make sure we can reach the $ENROLL_URL $PORT
SHORT_URL=$(/bin/echo "$ENROLL_URL" | /usr/bin/awk -F/ '{print $3}')
PORT_TEST=$(/usr/bin/nc -z "$SHORT_URL" "$PORT" >/dev/null 2>&1) 
PORT_TEST=$?
# Pull variables from $ENROLL_PLIST
if [ -f /private/var/root/Library/Preferences/$ENROLL_PLIST.plist ]; then
	if defaults read $ENROLL_PLIST catalog1 > /dev/null 2>&1 ; then
		CATALOG1=$(defaults read $ENROLL_PLIST catalog1)
	fi
	if defaults read $ENROLL_PLIST catalog2 > /dev/null 2>&1 ; then
		CATALOG2=$(defaults read $ENROLL_PLIST catalog2)
	fi
	if defaults read $ENROLL_PLIST catalog3 > /dev/null 2>&1 ; then
		CATALOG3=$(defaults read $ENROLL_PLIST catalog3)
	fi
	if defaults read $ENROLL_PLIST manifest1 > /dev/null 2>&1 ; then
		MANIFEST1=$(defaults read $ENROLL_PLIST manifest1)
	fi
	if defaults read $ENROLL_PLIST manifest2 > /dev/null 2>&1 ; then
		MANIFEST2=$(defaults read $ENROLL_PLIST manifest2)
	fi
	if defaults read $ENROLL_PLIST manifest3 > /dev/null 2>&1 ; then
		MANIFEST3=$(defaults read $ENROLL_PLIST manifest3)
	fi
	if defaults read $ENROLL_PLIST manifest4 > /dev/null 2>&1 ; then
		MANIFEST4=$(defaults read $ENROLL_PLIST manifest4)
	fi
fi
# get machine-specific variables
RECORDNAME=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial Number/ { print $4; }')
DISPLAYNAME=$(/usr/sbin/scutil --get ComputerName | /usr/bin/sed 's/ /-/g')
UUID=$(system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }')
## munki Variables
# Get the authorization information from ManagedInstallesPlist
AUTH=$( /usr/bin/defaults read /var/root/Library/Preferences/ManagedInstalls.plist AdditionalHttpHeaders | /usr/bin/awk -F 'Basic ' '{print $2}' | /usr/bin/sed 's/.$//' | /usr/bin/base64 --decode )
# Read the location of the ManagedInstallDir from ManagedInstall.plist
MANAGEDINSTALL_DIR="$(defaults read /Library/Preferences/ManagedInstalls ManagedInstallDir)"
# Make sure we're outputting our information to "ConditionalItems.plist" 
# (plist is left off since defaults requires this)
CONDITIONALITEMS_PLIST="$MANAGEDINSTALL_DIR/ConditionalItems"
# Make sure $MANAGEDINSTALL_DIR exists
# This will write the munki-enroll conditional items to /tmp/ConditionalItems.plist in case of a race condition.
if ! [ -z "$MANAGEDINSTALL_DIR" ] && [ ! -d "$MANAGEDINSTALL_DIR" ] ;then
	echo "Create_Directory- $MANAGEDINSTALL_DIR"
	mkdir -p "$MANAGEDINSTALL_DIR"
	else
	CONDITIONALITEMS_PLIST="/tmp/ConditionalItems"
fi
#######################
#######################
## Functions
# rootCheck
# Are we running as root? If not exit 1, if so set restrictive permissions
rootCheck() {
	if [ $EUID != 0 ]; then
	        echo "This script must be run as root. Please sudo accordingly."
		exit 1
		else
		chown root:wheel "${0}"
		chmod 750 "${0}"
	fi
}
# conditionInstall 
# Are we running as a munki Condition? If not cp "${0}" /usr/local/munki/conditions
conditionaInstall () {
	if [[ $SCRIPT_FOLDER = /usr/local/munki/conditions ]]; then	
		echo "Running as munki condition."
		else
		echo "Not running as munki condition. Attempting to copy script to /usr/local/munki/conditions."
		cp "${0}" /usr/local/munki/conditions
	fi
}

# munkiPORTTEST
# Can we reach "$SHORT_URL" "$PORT"? Report in conditional item "munki-enroll-PORT_TEST" 404 or 200. If 404 exit 1
munkiPORTTEST() {
	if [ $PORT_TEST != 0 ]; then
		echo "$SHORT_URL is not reachable on $PORT."
		# Note the key "munki-enroll-PORT_TEST" which becomes the condition that you would use in a predicate statement
		defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-PORT_TEST" -string "404"
		plutil -convert xml1 "$CONDITIONALITEMS_PLIST".plist
		echo "exit $PORT_TEST"
		exit $PORT_TEST
		else
		echo "$SHORT_URL is reachable on $PORT."
		# Note the key "munki-enroll-PORT_TEST" which becomes the condition that you would use in a predicate statement
		defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-PORT_TEST" -string "200"
		plutil -convert xml1 "$CONDITIONALITEMS_PLIST".plist
	fi
}

# manifestTEST
# Does $REPO_URL/manifest/$RECORDNAME exist? If not START_ENROLL=1. If so, is display_name the same as $DISPLAYNAME if not START_UPDATE=1
manifestTEST() {
	MANIFEST_TEST=$(curl --silent --head --user "$AUTH" "$REPO_URL/manifests/$RECORDNAME" | grep "200 OK" > /dev/null 2>&1)
	MANIFEST_TEST=$?
	if [ $MANIFEST_TEST = 0 ]; then
		TMP_DOWNLOAD=$(mktemp -d /tmp/munki-enroll.XXXXX)
		curl  --silent --user "$AUTH" "$REPO_URL/manifests/$RECORDNAME" -o "$TMP_DOWNLOAD/$RECORDNAME.plist"
		#plutil -convert binary1 "$TMP_DOWNLOAD/$RECORDNAME"
		MANIFEST_DISPLAYNAME=$(defaults read "$TMP_DOWNLOAD/$RECORDNAME.plist" "display_name")
		rm -rf "$TMP_DOWNLOAD"
		if [ $MANIFEST_DISPLAYNAME = $DISPLAYNAME ]; then
			defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-DISPLAYNAME" -string "$DISPLAYNAME"
			plutil -convert xml1 "$CONDITIONALITEMS_PLIST".plist		
		else
			START_UPDATE=1
		fi
	else
		START_ENROLL=1
	fi
}

# munkiENROLL
# Here's the munki-enroll meat.
munkiENROLL() {	
	echo "RECORDNAME = $RECORDNAME, DISPLAYNAME = $DISPLAYNAME, UUID = $UUID"
	echo "CATALOG1 = $CATALOG1, CATALOG2 = $CATALOG2, CATALOG3 = $CATALOG3" 
	echo "MANIFEST1 = $MANIFEST1, MANIFEST2 = $MANIFEST2, MANIFEST3 = $MANIFEST3, MANIFEST4 = $MANIFEST4"

	# Send information to the server to make the manifest
	# If you're not using basic authentication, then delete "-u "$AUTH" \"
	SUBMIT=`/usr/bin/curl --max-time 5 --get --silent\
  	  -d recordname="$RECORDNAME" \
  	  -d displayname="$DISPLAYNAME" \
  	  -d uuid="$UUID" \
  	  -d catalog1="$CATALOG1" \
  	  -d catalog2="$CATALOG2" \
  	  -d catalog3="$CATALOG3" \
  	  -d manifest1="$MANIFEST1" \
  	  -d manifest2="$MANIFEST2" \
  	  -d manifest3="$MANIFEST3" \
  	  -d manifest4="$MANIFEST4" \
  	  -u "$AUTH" \
	  "$ENROLL_URL"`
      
	echo $SUBMIT

	RESULT="${SUBMIT##*$'\n'}"
    
	if [ $RESULT = 9 ]; then	
		echo "Manifest $RECORDNAME for $DISPLAYNAME exists."
		exit $RESULT
	fi
	if [ $RESULT = 0 ]; then
		echo "Manifest $RECORDNAME for $DISPLAYNAME successfully created."
		exit $RESULT
	fi
}

# munkiUPDATE
# Here's the munki-enroll-update meat.
munkiUPDATE (){
	echo "RECORDNAME = $RECORDNAME, DISPLAYNAME = $DISPLAYNAME, UUID = $UUID"

	# Send information to the server to make the manifest
	# If you're not using basic authentication, then delete "-u "$AUTH" \"
	SUBMIT=`/usr/bin/curl --max-time 5 --get --silent\
  		-d function="update" \
  		-d recordname="$RECORDNAME" \
  		-d displayname="$DISPLAYNAME" \
  		-d uuid="$UUID" \
  		-u "$AUTH" \
  		"$UPDATE_URL"`
	 
	echo $SUBMIT

	RESULT="${SUBMIT##*$'\n'}"
	echo $RESULT
    
	if [ $RESULT = 0 ]; then
		# Note the key "munki-enroll" which becomes the condition that you would use in a predicate statement
		defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-update" -string "$RESULT"
		plutil -convert xml1 "$CONDITIONALITEMS_PLIST".plist
		echo "DisplayName ($DISPLAYNAME) upto date in on $SHORT_URL. exit $RESULT"
		exit $RESULT
		else
		# Note the key "munki-enroll" which becomes the condition that you would use in a predicate statement
		defaults write "$CONDITIONALITEMS_PLIST" "munki-enroll-update" -string "$RESULT"
		plutil -convert xml1 "$CONDITIONALITEMS_PLIST".plist
		echo "Error updating some computer name. exit $RESULT"
		exit $RESULT
	fi
}

#######################
## Main
# Are we running as root? If not exit 1, if so set restrictive permissions
rootCheck
# Are we running as a munki Condition? If not cp "${0}" /usr/local/munki/conditions
conditionaInstall
# Can we reach "$SHORT_URL" "$PORT"? Report in conditional item "munki-enroll-PORT_TEST" 404 or 200. If 404 exit 1
munkiPORTTEST
# Does $REPO_URL/manifest/$RECORDNAME exist?
manifestTEST
# If we need to, lets munkiENROLL
if [ "$START_ENROLL" = "1" ]; then
	munkiENROLL
fi
# If we need to, lets munkiUPDATE
if [ "$START_UPDATE" = "1" ]; then
	munkiUPDATE
fi
# If we make it here we didn't need anything
echo "No enroll or update needed."
exit 0
#######################