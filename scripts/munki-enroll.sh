#!/bin/bash 

##### This version of the script also assumes you have an https-enabled Munki server with basic authentication
##### If you do not change the SUBMITURL and PORT as needed. Also comment out "-u "$AUTH" \" 
##### Change SUBMITURL's variable value to your actual URL
##### 

#######################
## User-set variables
# Change this URL to the location fo your Munki Enroll install
SUBMITURL="https://munki.domain/repo/munki-enroll/enroll.php"
PORT=443
RUNFILE=/usr/local/munki/.runfile
RUNLIMIT=10
#######################

# folder containging script
SCRIPT_FOLDER=`dirname "$0"`

if [ $EUID != 0 ]; then
        echo "This script must be run as root. Please sudo accordingly."
	exit 1
fi

if [[ $SCRIPT_FOLDER = /usr/local/munki/conditions ]]; then	
	[[ ! -f "$RUNFILE" ]] && echo 0 > $RUNFILE
	COUNTER=$(tail -1 "$RUNFILE")
	CURRENTRUN=$(expr $COUNTER + 1)
	echo "$CURRENTRUN" > "$RUNFILE"
	echo "Running as munki condition. Run $CURRENTRUN."
	if [[ $CURRENTRUN -gt $RUNLIMIT ]]; then
		echo "Exceded runlimit. Removing ${0} and giving up. ¯\_(ツ)_/¯"	
		rm ${0}
		rm $RUNFILE
		exit $RUNLIMIT
	fi
fi

# Make sure we can reach the $SUBMITURL $PORT
SHORTURL=$(/bin/echo "$SUBMITURL" | /usr/bin/awk -F/ '{print $3}')
PORTTEST=$(/usr/bin/nc -z "$SHORTURL" "$PORT") 
PORTTEST=$?

if [ $PORTTEST != 0 ]; then
	# Read the location of the ManagedInstallDir from ManagedInstall.plist
	managedinstalldir="$(defaults read /Library/Preferences/ManagedInstalls ManagedInstallDir)"
	# Make sure we're outputting our information to "ConditionalItems.plist" 
	# (plist is left off since defaults requires this)
	plist_loc="$managedinstalldir/ConditionalItems"
	# Note the key "munki-enroll" which becomes the condition that you would use in a predicate statement
	defaults write "$plist_loc" "munki-enroll" -string "UNREACHABLE"
	plutil -convert xml1 "$plist_loc".plist
	
	if [[ $SCRIPT_FOLDER != /usr/local/munki/conditions ]]; then
		echo "Can't contact the server on port $PORT."
		echo "Copying to /usr/local/munki/conditions"
		cp ${0} /usr/local/munki/conditions
		exit $PORTTEST
	else
	echo "Can't contact the server on port $PORT."
	exit $PORTTEST
	fi
fi

if [ "$PORTTEST" = 0 ]; then
	# Get the serial number and computer name and hardware UUID
	RECORDNAME=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial Number/ { print $4; }')
	DISPLAYNAME=$(/usr/sbin/scutil --get ComputerName | /usr/bin/sed 's/ /-/g')
	UUID=$(system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }')

	echo "RECORDNAME = $RECORDNAME, DISPLAYNAME = $DISPLAYNAME, UUID = $UUID"

	# Get the authorization information from ManagedInstallesPlist
 	AUTH=$( /usr/bin/defaults read /var/root/Library/Preferences/ManagedInstalls.plist AdditionalHttpHeaders | /usr/bin/awk -F 'Basic ' '{print $2}' | /usr/bin/sed 's/.$//' | /usr/bin/base64 --decode )

	# Send information to the server to make the manifest
	SUBMIT=`/usr/bin/curl --max-time 5  --get --silent\
  	  -d recordname="$RECORDNAME" \
  	  -d displayname="$DISPLAYNAME" \
  	  -d uuid="$UUID" \
  	  -u "$AUTH" \
	  "$SUBMITURL"`
  	  
    # If not basic authentication, then comment out "-u "$AUTH" \"
      
	echo $SUBMIT

	RESULT="${SUBMIT##*$'\n'}"
    
	if [ $RESULT = 9 ] && [[ $SCRIPT_FOLDER = /usr/local/munki/conditions ]]; then	
		echo "Manifest exists. Removing script from /usr/local/munki/conditions."
		rm ${0}
		[[ -f "$RUNFILE" ]] && rm "$RUNFILE"
		exit $RESULT
	fi
	if [ $RESULT = 0 ] && [[ $SCRIPT_FOLDER = /usr/local/munki/conditions ]]; then
		echo "Manifest created. Removing script from /usr/local/munki/conditions."
		rm ${0}
		[[ -f "$RUNFILE" ]] && rm "$RUNFILE"
		exit $RESULT
	fi
	exit $RESULT
	else
	exit -1
fi
