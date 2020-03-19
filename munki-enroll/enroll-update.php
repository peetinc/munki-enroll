<?php
namespace CFPropertyList;

// require cfpropertylist
require_once 'cfpropertylist-2.0.1/CFPropertyList.php';
require_once 'logger.php';

// Manifest Relative path (include trailing / i.e. '../manifests/')
$manifestspath = '../manifests/';

//Set default manifest and catalog
$defaultmanifest = 'Management/Mandatory';
$defaultcatalog = 'production';

// Get the varibles passed by the enroll script
//if $function is not passed, set to enroll
if (!($recordname = filter_input(INPUT_GET, 'function', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES)))
	{
		$function = 'enroll'; 
	}
//if $recordname is not passed, set to _NOT-PROVIDED_
if (!($recordname = filter_input(INPUT_GET, 'recordname', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES)))
	{
		$recordname = '_NOT-PROVIDED_'; 
	}
//if $displayname is not passed, set to _NOT-PROVIDED_
if (!($displayname = filter_input(INPUT_GET, 'displayname', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES)))
	{
		$displayname = '_NOT-PROVIDED_'; 
	}
//if $catalog1 is not passed, set to $defaultcatalog
if (!($catalog1 = filter_input(INPUT_GET, 'catalog1', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES)))
	{
		$catalog1 = $defaultcatalog; 
	}
//if $manifest1 is not passed, set to $defaultmanifest
if (!($manifest1 = filter_input(INPUT_GET, 'manifest1', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES))) 
	{
		$manifest1 = $defaultmanifest; 
	}
$manifest2 = filter_input(INPUT_GET, 'manifest2', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);
$manifest3 = filter_input(INPUT_GET, 'manifest3', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);
$manifest4 = filter_input(INPUT_GET, 'manifest4', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);
$catalog2 = filter_input(INPUT_GET, 'catalog2', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);
$catalog3 = filter_input(INPUT_GET, 'catalog3', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);
$uuid = filter_input(INPUT_GET, 'uuid', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES);

function varCheck($recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
// end if no variables provided
if ( $recordname == "_NOT-PROVIDED_" or $displayname == "_NOT-PROVIDED_" or $uuid = "_NOT-PROVIDED_" )
	{
		echo "Please provide recordname, displayname and uuid at minimum.\n";
		echo "Checking out now.\n\n";
		echo "1";
		$result = 'FAILURE - NOT ENOUGH ARGUMENTS';
		logger($result, $recordname, $displayname, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
		exit(1);
	}
}

function existingRecordCheck($recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
// Check if manifest already exists for this machine
echo "MUNKI-ENROLL. Checking for existing manifests.\n\n";

if ( file_exists( $manifestspath . $recordname ) )
	{
		echo "Computer manifest " . $recordname . " already exists.\n";
		echo "You're trying to be naughty.\n";
		echo "9";
		$result = 'FAILURE - EXISTING MANIFEST';
		logger($result, $recordname, $displayname, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
		exit(9);
    }
}

function nestCheck($recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
// Ensure we aren't nesting a manifest within itself
if ( $manifest1 == $recordname or $manifest2 == $recordname or $manifest3 == $recordname or $manifest4 == $recordname )
	{
		echo "You've atempted to add " . $recordname . " to it's own included_manifests array.\n";
		echo "That is naughty.\n";
		echo "Please ensure that manifest1, manifest2, manifest3, and/or manifest4 is not set to " . $recordname . ".\n";
		echo "Checking out now.\n\n";
		echo "1";
		$result = 'FAILURE - RECURSIVE MANIFSEST';
		logger($result, $recordname, $displayname, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
		exit(1);
	}
}

function enroll($recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
//A bit of verbosity never hurt anyone.
echo "Computer manifest does not exist. Will create.\n\n";
echo "Just a heads up, if the displayname you provided should be unique for ease of identification.\n";
echo "Here's hoping you changed the computername before enrolling.\n";


if ( $manifest1 != $defaultmanifest or $manifest2 != "" or $manifest3 != "" or $manifest4 != "" )
	{
		echo "Another heads up, if the manifests you provided are not valid, they will still be included. There is no error checking.\n";
	}

if ( $catalog1 != $defaultcatalog )
	{
		echo "Another heads up, if the catalog name you provided is not valid, it will still be included. There is no error checking.\n";
	}

$plist = new CFPropertyList();
$plist->add( $dict = new CFDictionary() );
        
	// Add manifest to production catalog by default
	$dict->add( 'catalogs', $array = new CFArray() );
	if ( $catalog1 != "" )
		{
			$array->add( new CFString( $catalog1 ) );
		}
    if ( $catalog2 != "" )
		{
			$array->add( new CFString( $catalog2 ) );
		}
	if ( $catalog3 != "" )
		{
			$array->add( new CFString( $catalog3 ) );
		}
		
	//Add Display Name
	$dict->add( 'display_name', new CFString( $displayname ) );
    
	//Add UUID
	if ( $uuid != "" )
		{
			$dict->add( 'notes', new CFString( $uuid ) );
			$dict->add( 'uuid', new CFString( $uuid ) );
		}
        
    // Add parent manifest to included_manifests to achieve waterfall effect
	$dict->add( 'included_manifests', $array = new CFArray() );
	if ( $manifest1 != "" )
		{
			$array->add( new CFString( $manifest1 ) );
		}
	if ( $manifest2 != "" )
		{
			$array->add( new CFString( $manifest2 ) );
		}
	if ( $manifest3 != "" )
		{
		$array->add( new CFString( $manifest3 ) );
		}
	if ( $manifest4 != "" )
		{
			$array->add( new CFString( $manifest4 ) );
		}

	// Format the plist
	// Save the newly created plist
	$xml = $plist->toXML($formatted=true);
	file_put_contents($manifestspath . $recordname, $xml);
	//$plist->saveXML( '../manifests/' . $recordname );
    
	echo "\nNew manifest created: " . $recordname . "\n";
	echo "New manifest display_name: " . $displayname . "\n";
	echo "Included Manifest(s): " . $manifest1 . " " . $manifest2 . " " . $manifest3 . " " . $manifest4 . "\n\n";
	echo "0";
	$result = 'SUCCESS';
	logger($result, $recordname, $displayname, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
}

function update($manifestspath, $recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
	// Read existing manifest
	$manifestplist = new CFPropertyList( $manifestspath . $recordname );
	////
	//Just a handy way to visualize the existing manifest.
	//echo '<pre>';
	//var_dump( $manifestplist->toArray() );
	//echo '</pre>';
	////
	//Dump existing manifest plist to php array
	$manifestarrayORIG = $manifestplist->toArray();
	$manifestarrayNEW = $manifestplist->toArray();
	//Get existing displayname_name and uuid from manifest
	$olddisplayname = $manifestarrayNEW[ 'display_name' ];
	if (!($olduuid = $manifestarrayNEW[ 'uuid' ])) {
		$olduuid = '_OLDUUID-NOT-FOUND_';
	}
	// check UUID's Bail if not the same
	if ( $uuid == $olduuid ) {
		echo "UUID match ... ";
		}
		else {
		echo "UUID mismatch. We out ... Exit \n\n";
		echo "99";
		exit(99);
	}
	// Check diskplay_name, update in array if needed
	if ( $displayname == $olddisplayname ) {
		echo "DisplayName match ... ";
		}
		else {
		echo "DisplayName mismatch. Updating DisplayName to $displayname ... ";
		$manifestarrayNEW[ 'display_name' ] = $displayname;
		//$namecheck = $manifestarrayNEW[ 'display_name' ];
		//echo "New name in array is $namecheck ... ";
		}
	// Cheick if anything has been updated
	if ( $manifestarrayORIG == $manifestarrayNEW ) {
		echo "Nothing to update ... ";
		}
		else {
		$newmanifestplist = new CFPropertyList();
		$td = new CFTypeDetector();
		$guessedStructure = $td->toCFType( $manifestarrayNEW );
		$newmanifestplist->add( $guessedStructure );
		$newmanifestplist->saveXML( $manifestspath . $recordname.'.tmp' );
		
		if (!unlink($manifestspath.$recordname)) {  
    		echo ("ERROR: $manifestspath.$recordname cannot be deleted ... ");  
		}  
		else {  
    		echo ("$manifestspath.$recordname has been deleted ... ");  
		}  
		if (!rename($manifestspath.$recordname.'.tmp',$manifestspath.$recordname)) {  
			echo ("ERROR: $manifestspath.$recordname.'.tmp' cannot be renamed ... ");  
		}  
		else {  
			echo ("$manifestspath.$recordname has been updated ... ");  
		}  
		}
		echo "INFO: End of updateManifest ... ";		
}

?>