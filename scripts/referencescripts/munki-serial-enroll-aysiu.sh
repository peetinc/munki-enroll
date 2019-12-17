#!/bin/sh 

##### Tweak on the original Munki-Enroll
##### This has different logic based on whether the computer is a desktop or a laptop
##### If it's a laptop, the script grabs the user's full name
##### If it's a desktop, the script just grabs the computer's name
##### This version of the script also assumes you have an https-enabled Munki server with basic authentication
##### Change SUBMITURL's variable value to your actual URL
##### Also change YOURLOCALADMINACCOUNT if you have one

#######################
## User-set variables
# Change this URL to the location fo your Munki Enroll install
SUBMITURL="https://your.companyname.com/path/to/enroll.php"
# Change this to a local admin account you have if you have one
ADMINACCOUNT="YOURLOCALADMINACCOUNT"
#######################

# Make sure there is an active Internet connection
SHORTURL=$(/bin/echo "$SUBMITURL" | /usr/bin/awk -F/ '{print $3}')
PINGTEST=$(/sbin/ping -o -t 4 "$SHORTURL" | /usr/bin/grep "64 bytes")

if [ ! -z "$PINGTEST" ]; then

   # Always get the serial number
   SERIAL=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Serial Number/ { print $4; }')

   # Determine if it's a laptop or a desktop
   LAPTOPMODEL=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/grep "Model Identifier" | /usr/bin/grep "Book" | /usr/bin/awk -F ": " '{print $2}')

   # If it's a desktop...
   if [ -z "$LAPTOPMODEL" ]; then

      # Make the manifest template desktop
      TEMPLATE="desktop"

      # Make the "display name" into the actual computer name
      DISPLAYNAME=$(/usr/sbin/scutil --get ComputerName | /usr/bin/sed 's/ /-/g')

   # If it's a laptop...
   else
   
      # Make the manifest template laptop
      TEMPLATE="laptop"

      # Get the primary user
      PRIMARYUSER=''
      # This is a little imprecise, because it's basically going by process of elimination, but that will pretty much work for the setup we have
      /usr/bin/cd /Users
      for u in *; do
         if [ "$u" != "Guest" ] && [ "$u" != "Shared" ] && [ "$u" != "root" ] && [ "$u" != "$ADMINACCOUNT" ]; then
            PRIMARYUSER="$u"
         fi
      done
   
      if [ "$PRIMARYUSER" != "" ]; then
         
         # Add real name (not just username) of user
         DISPLAYNAME=$(/usr/bin/dscl . -read /Users/"$PRIMARYUSER" dsAttrTypeStandard:RealName | /usr/bin/sed 's/RealName://g' | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/^ *//;s/ *$//' | /usr/bin/sed 's/ /%20/g')   
         # Add laptop model
         DISPLAYNAME+="%20($LAPTOPMODEL)"

      else
         
         DISPLAYNAME="Undefined%20-%20Fix%20Later"
      fi

   # End checking for desktop v. laptop
   fi

   # Get the authorization information
   AUTH=$( /usr/bin/defaults read /var/root/Library/Preferences/ManagedInstalls.plist AdditionalHttpHeaders | /usr/bin/awk -F 'Basic ' '{print $2}' | /usr/bin/sed 's/.$//' | /usr/bin/base64 --decode )

   # Send information to the server to make the manifest
   /usr/bin/curl --max-time 5 --silent --get \
      -d displayname="$DISPLAYNAME" \
      -d serial="$SERIAL" \
      -d template="$TEMPLATE" \
      -u "$AUTH" "$SUBMITURL"
      # If not basic authentication, then just "$SUBMITURL" for the last line 

   # Delete the ClientIdentifier, since we'll be using the serial number
   function deleteClientIdentifier {
      clientIdentifier=$(/usr/bin/defaults read "$1" | /usr/bin/grep "ClientIdentifier")
      if [ ! -z "$clientIdentifier" ]; then
         /usr/bin/defaults delete "$1" ClientIdentifier
      fi 
   }
   
   deleteClientIdentifier "/Library/Preferences/ManagedInstalls"
   deleteClientIdentifier "/var/root/Library/Preferences/ManagedInstalls"

else
   # No good connection to the server
   exit 1
fi