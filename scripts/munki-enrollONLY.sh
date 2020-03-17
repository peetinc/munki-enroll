#!/bin/bash 

##### This version of the script assumes you have an https-enabled Munki server with basic authentication
##### If you do not change the ENROLLURL and PORT as needed. Also remove (don't comment out) "-u "$AUTH" \" 
##### Change ENROLLURL's variable value to your actual URL
##### This script must be run as root to access $ENROLLPLIST and /var/root/Library/Preferences/ManagedInstalls.plist

#######################
## User-set variables
# Change this URL to the location fo your Munki Enroll install
ENROLLURL="https://munki.domain/repo/munki-enroll/enroll.php"
PORT=443
RUNFILE=/usr/local/munki/.runfile
RUNLIMIT=10
#Catalogs and Manifests - Hard code these variables or write them into /private/var/root/Library/$ENROLLPLIST.plist
#Values set in $ENROLLPLIST override values set here. However, if CATALOG2 is defined here, not a key in $ENROLLPLIST.plist the value defined below will be used
ENROLLPLIST=tld.yourdomain.munki-enroll
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

# folder containging script
SCRIPT_FOLDER=`dirname "$0"`

# Quick root check
if [ $EUID != 0 ]; then
        echo "This script must be run as root. Please sudo accordingly."
	exit 1
	else
	chown root:wheel "${0}"
	chmod 750 "${0}"
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

# Make sure we can reach the $ENROLLURL $PORT
SHORTURL=$(/bin/echo "$ENROLLURL" | /usr/bin/awk -F/ '{print $3}')
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
	
	#
	if [ -f /private/var/root/Library/Preferences/$ENROLLPLIST.plist ]; then
		if defaults read $ENROLLPLIST catalog1 > /dev/null 2>&1 ; then
			CATALOG1=$(defaults read $ENROLLPLIST catalog1)
		fi
		if defaults read $ENROLLPLIST catalog2 > /dev/null 2>&1 ; then
			CATALOG2=$(defaults read $ENROLLPLIST catalog2)
		fi
		if defaults read $ENROLLPLIST catalog3 > /dev/null 2>&1 ; then
			CATALOG3=$(defaults read $ENROLLPLIST catalog3)
		fi
		if defaults read $ENROLLPLIST manifest1 > /dev/null 2>&1 ; then
			MANIFEST1=$(defaults read $ENROLLPLIST manifest1)
		fi
		if defaults read $ENROLLPLIST manifest2 > /dev/null 2>&1 ; then
			MANIFEST2=$(defaults read $ENROLLPLIST manifest2)
		fi
		if defaults read $ENROLLPLIST manifest3 > /dev/null 2>&1 ; then
			MANIFEST3=$(defaults read $ENROLLPLIST manifest3)
		fi
		if defaults read $ENROLLPLIST manifest4 > /dev/null 2>&1 ; then
			MANIFEST4=$(defaults read $ENROLLPLIST manifest4)
		fi
	fi
		
	
	# Get the serial number and computer name and hardware UUID
	RECORDNAME=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial Number/ { print $4; }')
	DISPLAYNAME=$(/usr/sbin/scutil --get ComputerName | /usr/bin/sed 's/ /-/g')
	UUID=$(system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }')

	echo "RECORDNAME = $RECORDNAME, DISPLAYNAME = $DISPLAYNAME, UUID = $UUID"
	echo "CATALOG1 = $CATALOG1, CATALOG2 = $CATALOG2, CATALOG3 = $CATALOG3" 
	echo "MANIFEST1 = $MANIFEST1, MANIFEST2 = $MANIFEST2, MANIFEST3 = $MANIFEST3, MANIFEST4 = $MANIFEST4"

	# Get the authorization information from ManagedInstallesPlist
 	AUTH=$( /usr/bin/defaults read ManagedInstalls AdditionalHttpHeaders | /usr/bin/awk -F 'Basic ' '{print $2}' | /usr/bin/sed 's/.$//' | /usr/bin/base64 --decode )

	# Send information to the server to make the manifest
	# If you're not using basic authentication, then delete "-u "$AUTH" \"
	SUBMIT=`/usr/bin/curl --max-time 5  --get --silent\
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
	  "$ENROLLURL"`
      
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
