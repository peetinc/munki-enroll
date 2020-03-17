# munki-enroll
A lovingly updated `munki-enroll`.

A set of scripts to automatically enroll clients in Munki, allowing for a very flexible manifest structure.

This version is a deeply modified rewrite of the original, Copyright (c) 2012 Cody Eding, to suit my (and hopefully your) needs .
See below and LICENSE file for licensing details.

## Essential Reading

Before you even think about using any Munki Enroll, or anything like these projects, please read [An opinionated guide to Munki manifests](https://groob.io/posts/manifest-guide/) and [Another opinionated guide to Munki manifests](http://technology.siprep.org/another-opinionated-guide-to-munki-manifests/) first.

## Why Yet Another Munki Enroll?

I just needed something a bit cleaner with some error checking and recovery. I also wanted something to turn run as a conditional item so it would/could/can/does update the display_name of the record when it's changed. Just a preference for my environments.

## How does this differ from regular Munki Enroll's?

Like [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/) and [grahampugh/munki-enroll](https://github.com/grahampugh/munki-enroll/), [peetinc/munki-enroll](https://github.com/peetinc/munki-enroll/) focuses on a one manifest per client workflow. See above for more reading, but unlike [aysiu/munki-serial-enroll](https://github.com/aysiu/munki-serial-enroll/), this project uses [TECLIB/CFPropertyList](https://github.com/TECLIB/CFPropertyList)], it may be a bit long in tooth, but it profides an infinitely more flexibly fremwork for creating and updating manifests.

## Installation

Munki Enroll requires PHP to be working on the webserver hosting your Munki repository. As well as www write access to `manifests`.

Copy the "munki-enroll" folder to the root of your Munki repository (the same directory as pkgs, pkginfo, manifests and catalogs). 

Make sure your www user can write to `manifests` and `munki-enroll/logs/`

Define the following in `enroll.php`:

	$defaultmanifest = 'Default/Manifest';
	$defaultcatalog = 'production';

## Client Configuration

The included `munki-enroll.sh` or `munki-enrollONLY.sh` scripts needs a couple variables set:

	REPO_URL="https://munki.domain/repo"
	ENROLL_URL="$REPO_URL/munki-enroll/enroll.php"
	UPDATE_URL="$REPO_URL/munki-enroll/update.php"
	PORT=443
	ENROLL_PLIST=domain.munki.munki-enroll (if staging a /private/var/root/Library/Preferences/$ENROLL_PLIST.plist)
	RUNFILE=/usr/local/munki/.runfile (only if using munki-enrollONLY.sh)
	RUNLIMIT=10 (only if using munki-enrollONLY.sh)
	
Optionally you can add these as well:
	CATALOG1=(This will be set for you in `enroll.php`)
	CATALOG2=
	CATALOG2=
	MANIFEST1=(This will be set for you in `enroll.php`)
	MANIFEST2=
	MANIFEST3=
	MANIFEST4=

If `munki-enroll.sh`runs anywhere but from `/usr/munki/conditions` it will copy itself into `/usr/munki/conditions` to keep your computers enrolled/display_name up-to-date.

If `munki-enrollONLY.sh` fails to contact your `SUBMITURL`on `PORT`, it moves itself into `/usr/munki/conditions` and runs as any other Conditional Items. If it successfully creates a manifest or finds that there's a manifest with its `RECORDNAME` (defaulted to computer serial number) it deletes itself from `/usr/munki/conditions`. 

## Things to Know

Currently theres a bit of error checking both server-side in `enroll.php` and in `munki-enroll.sh`:
- `enroll.php` won't let an existing record be overwritten.
- `enroll.php` won't run without `RECORDNAME` , `DISPLAYNAME` and `UUID` .
- `munki-enroll.sh` will drop into `/usr/munki/conditions` if it runs from anywhere but `/usr/munki/conditions` and run as a Conditional Item with managedsoftwareupdate.
- `munki-enrollONLY.sh` will drop into `/usr/munki/conditions` if it fails to contact your `SUBMITURL`on `PORT` and will run as a Conditional Item with managedsoftwareupdate.
- Theres a `RUNLIMIT` for `munki-enrollONLY.sh` when running from `/usr/munki/conditions` as well. If exceeded, the `munki-enroll.sh` gives up and self destructs.

Some niceties and expectations:
- `update.php` validates requests with the `UUID` of the computer. It currently only updates `display_name`.
- `enroll.php` has a logging facility that logs to `/munki-enroll/log/munki-enroll.log` just in case there are some rouge requests out there
- `enroll.php` as a few exit codes:
	- `0` successful creation of a new manifest
	- `1` not enough arguments
	- `9` manifest exists 
- `enroll.php` can accept up to four included manifests. Simply provide `CATALOG1`, `CATALOG2` and/or `CATALOG3` as well as `MANIFEST1`, `MANIFEST2`, `MANIFEST3` and/or `MANIFEST4` variables in the script. `CATALOG1`and `MANIFEST1` defaults are built into `enroll.php`
- `munki-enroll.sh` and `munki-enrollONLY.sh` will read `CATALOG1`, `CATALOG2` and/or `CATALOG3` as well as `MANIFEST1`, `MANIFEST2`, `MANIFEST3` and/or `MANIFEST4` from `/private/var/root/Library/Preferences/$ENROLLPLIST.plist`
- `munki-enroll.sh` and `munki-enrollONLY.sh` must be run as root.
- `munki-enroll.sh` and `munki-enrollONLY.sh` pushes the computer `UUID` to `enroll.php` which drops it into a `notes` and `uuid` strings.
- `munki-enroll.sh` and `munki-enrollONLY.sh` pulls `AdditionalHttpHeaders` from `ManagedInstalls` with the expectation that your repo is protected by HTTP Basic Authentication. If you are limiting access to `enroll.php` without Basic Authentication, simply remove `-u "$AUTH" \` from the curl statements.

## [License](https://github.com/peetinc/munki-enroll/blob/master/LICENSE)

Munki Enroll, like the contained CFPropertyList project, is published under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
