# munki-enroll
A lovingly updated `munki-enroll`.

A set of scripts to automatically enroll clients in Munki, allowing for a very flexible manifest structure.

This version is a deeply modified rewrite of the original, Copyright (c) 2012 Cody Eding, to suit my (and hopefully your) needs .
See below and LICENSE file for licensing details.

## Essential Reading

Before you even think about using any Munki Enroll, or anything like these projects, please read [An opinionated guide to Munki manifests](https://groob.io/posts/manifest-guide/) and [Another opinionated guide to Munki manifests](http://technology.siprep.org/another-opinionated-guide-to-munki-manifests/) first.

## Why Yet Another Munki Enroll?

I just needed something a bit cleaner with some error checking and recovery.

## How does this differ from regular Munki Enroll's?

Like [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/) and [grahampugh/munki-enroll](https://github.com/grahampugh/munki-enroll/), [peetinc/munki-enroll](https://github.com/peetinc/munki-enroll/) focuses on a one manifest per client workflow. See above for more reading, but unlike [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/), this project uses [TECLIB/CFPropertyList](https://github.com/TECLIB/CFPropertyList)], it may be a bit long in tooth, but it profides an infinitely more flexibly fremwork for createing and hopefully managing and updating manifests. Seriously, who doesn't want the option update the display_name when the computer name changes? (Okay, A LOT of people, but I really do want that bit of cleanliness.)

## Installation

Munki Enroll requires PHP to be working on the webserver hosting your Munki repository. As well as www write access to `manifests`.

Copy the "munki-enroll" folder to the root of your Munki repository (the same directory as pkgs, pkginfo, manifests and catalogs). 

Make sure your www user can write to `manifests` and `munki-enroll/logs/`

## Client Configuration

The included munki-enroll.sh script needs a couple bits set:

	SUBMITURL="https://munki.domain/repo/munki-enroll/enroll.php"
	PORT=443
	RUNFILE=/usr/local/munki/.runfile
	RUNLIMIT=10

If `munki-enroll.sh` fails to contact your `SUBMITURL`on `PORT`, it moves itself into `/usr/munki/conditions` and runs other Conditional Items. If it successfully creates a manifest or finds that theres a manifest with its `RECORDNAME` (defaulted to computer serial number) it deletes itself from `/usr/munki/conditions`. 

## Things to Know

Currently theres a bit of error checking both server-side in `enroll.php` and in `munki-enroll.sh`:
- `enroll.php` won't let an existing record be overwritten.
- `enroll.php` won't run without `RECORDNAME` and `DISPLAYNAME` .
- `munki-enroll.sh` will drop into `/usr/munki/conditions` if it fails to contact your `SUBMITURL`on `PORT` and will run as a Conditional Item with managedsoftwareupdate.
- Theres a `RUNLIMIT` wen running from `/usr/munki/conditions` as well. If exceeded, the `munki-enroll.sh` gives up and self destructs.

Some niceties and expectations:
- `enroll.php` has a logging facility that logs to `/munki-enroll/log/munki-enroll.log` just in case there are some rouge requests out there
- `enroll.php` as a few exit codes. 
	- `0` successful creation of a new manifest
	- `1` not enough arguments
	- `9`	manifest exists 
- `enroll.php` can accept up to four included manifests. Simple provide manifest1, manifest2, manifest3 and/or manifest4 variables to it.
- `munki-enroll.sh` must be run as root.
- `munki-enroll.sh` pushes the computer `UUID` to `enroll.php` which drops it into a `notes` and `uuid` strings.
- `munki-enroll.sh` pulls `AdditionalHttpHeaders` from `ManagedInstalls` with the expectation that your repo is protected by HTTP Basic Authentication. If you are limiting access to `enroll.php` without Basic Authentication, simply remove `-u "$AUTH"` from the curl statement.

## [License](https://github.com/peetinc/munki-enroll/blob/master/LICENSE)

Munki Enroll, like the contained CFPropertyList project, is published under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
