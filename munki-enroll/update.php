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
//if $uuid is not passed, set to _NOT-PROVIDED_
if (!($uuid = filter_input(INPUT_GET, 'uuid', FILTER_SANITIZE_STRING, FILTER_FLAG_NO_ENCODE_QUOTES))) 
	{
		$uuid = '_NOT-PROVIDED_'; 
	}

//Functions
function updateManifest($manifestspath, $recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {
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
	if ( $uuid !== $olduuid && $olduuid != '_OLDUUID-NOT-FOUND_' ) {
		echo "UUID mismatch! We out ... Exit \n\n";
		echo "99";
		exit(99);
	}
	// Check UUID is missing add if it is
	if ( $olduuid = '_OLDUUID-NOT-FOUND_' ) {
		echo "UUID missing. Updating UUID to $uuid ... ";
		$manifestarrayNEW[ 'uuid' ] = $uuid;
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
		$xml = $newmanifestplist->toXML($formatted=true);
		file_put_contents($manifestspath . $recordname.'.tmp', $xml);
		//$newmanifestplist->saveXML( $manifestspath . $recordname.'.tmp' );
		
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

// end if no variables provided
if ( $recordname == "_NOT-PROVIDED_" or $displayname == "_NOT-PROVIDED_" or $uuid == "_NOT-PROVIDED_" )
	{
		echo "Please provide recordname, displayname and uuid at minimum.\n";
		echo "Checking out now.\n\n";
		echo "1";
		$result = 'FAILURE - NOT ENOUGH ARGUMENTS';
		logger($result, $recordname, $displayname, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
		exit(1);
	}
	
// Check if manifest already exists for this machine
echo "MUNKI-UPDATER. Checking for existing manifests ... \n\n";


if ( file_exists( $manifestspath . $recordname ) )
	{
	echo "Existing Manifest found ...\n\n";
	updateManifest($manifestspath, $recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4);
	}
	else {
	echo "ERROR: No Manifest to Update. Exit \n\n";
	echo "1";
	exit(1);
	}

echo "INFO: End of update.php. Exit \n\n";
echo "0";
exit(0);

?>