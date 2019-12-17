# munki-enroll
A lovingly updated munki-enroll.

A set of scripts to automatically enroll clients in Munki, allowing for a very flexible manifest structure.

This version is my a deeply modified rewrite of the original, Copyright (c) 2012 Cody Eding, to suit my (and hopefully your) needs .
See below and LICENSE file for licensing details.

## Essential Reading
Before you even think about using Munki Serial Enroll, Munki Enroll, or anything like these projects, please read [An opinionated guide to Munki manifests](https://groob.io/posts/manifest-guide/) and [Another opinionated guide to Munki manifests](http://technology.siprep.org/another-opinionated-guide-to-munki-manifests/) first.

## Why Yet Another Munki Enroll?

I just needed something a bit cleaner with some error checking and recovery.

## How does this differ from regular Munki Enroll's?

Like [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/) and [grahampugh/munki-enroll](https://github.com/grahampugh/munki-enroll/), [peetinc/munki-enroll](https://github.com/peetinc/munki-enroll/) focuses on a one manifest per client workflow. See above for more reading, but unlike [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/), this project uses [TECLIB/CFPropertyList](https://github.com/TECLIB/CFPropertyList)], it may be a bit long in tooth, but it profides an infinitely more flexibly fremwork for createing and hopefully managing and updating manifests. Seriously, who doesn't want the option update the display_name when the computer name changes? (Okay, A LOT of people, but I really do want that bit of cleanliness.)

## Installation

Munki Enroll requires PHP to be working on the webserver hosting your Munki repository. As well as www write access to /YOURREPO/manifests.

Copy the "munki-enroll" folder to the root of your Munki repository (the same directory as pkgs, pkginfo, manifests and catalogs). 

Make sure your www user can write to /YOURREPO/manifests and /YOURREPO/munki-enroll/logs/

## Client Configuration

The included munki-enroll.sh script needs a couple bits set:

	SUBMITURL="https://munki.domain/repo/munki-enroll/enroll.php"
	PORT=443
	RUNFILE=/usr/local/munki/.runfile
	RUNLIMIT=10

	SUBMITURL="https://munki/munki-enroll/enroll.php"



## Caveats

Currently, Munki Enroll lacks any kind of error checking. It works perfectly fine in my environment without it. Your mileage may vary.

Your web server must have access to write to your Munki repository. I suggest combining SSL and Basic Authentication (you're doing this anyway, right?) on your Munki repository to help keep nefarious things out. To do this, edit the CURL command in munki_enroll.sh to include the following flag:

	--user "USERNAME:PASSWORD;" 

## License

Munki Enroll, like the contained CFPropertyList project, is published under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
