#!/usr/bin/perl -w
############################################################################################
#
# Perl source file for project deleteme
# Purpose: Fix item database errors.
# Method:  Symphony API
#
# Audit and fix holds that point to invalid items resulting in item
# database errors.
#    Copyright (C) 2016  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Thu Nov 19 14:26:00 MST 2016
# Rev:
#          0.11.00  - '-U' now runs cat keys identified to be fixed through fixholds (SD).
#          0.10.02  - Add -f to force inclusion of a location as non-holdable.
#          0.10.01  - Report each title only once.
#          0.10.00  - Added -H to handle a file of hold keys.
#          0.9.00   - Added '-c' flag.
#          0.8.00_e - Fixed ordering of usage flags.
#          0.8.00_d - Forgot to activate -V.
#          0.8.00_c - Updated usage notes.
#          0.8.00_b - Refactored get policy of non-hold-able locations.
#          0.8.00_a - Fixed usage notes.
#          0.8.00 - Added -V restrict holds by call number.
#          0.7.00 - Added -d debug.
#          0.6.00 - Only consider moving holds to items that have the circulate flag set to 'Y'.
#          0.5.00 - Dynamically generated non-holdable locations.
#          0.4.01_a - Updated usage.
#          0.4.01 - Handle multiple hold keys that refer to an non-viable item.
#          0.4.00 - -I Take an item ID as an argument.
#          0.3.00 - -i Shuffle holds by item key.
#          0.2.02 - -v verbose output.
#          0.2.00 - -u for user id.
#          0.1.04 - Added -r, -i for hold key, refactored and tested.
#          0.1.02 - Added temp file path to broken holds.
#          0.1.01 - Fix hold count error reporting.
#          0.1 - Production.
#          0.0 - Dev.
# Dependencies: pipe.pl, selhold, selitem, getpathname, getpol, fixholds.
#
###############################################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Item database errors occur on accounts when the customer has a hold who's
# hold key contains an item key that no longer exists. We are not sure how
# this happens but suspect that demand management either selects an item that
# is then removed like a DISCARD, or fails to update items that have been
# discarded to valid item keys. No matter, fixing the issues requires finding
# the errant hold and changing it to point to an item in a valid current location.
#
# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################
my $VERSION            = qq{0.11.00};
chomp( my $TEMP_DIR    = `getpathname tmp` );
chomp( my $TIME        = `date +%H%M%S` );
chomp( my $DATE        = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
chomp( my $BINCUSTOM   = `getpathname bincustom` );
my $BROKEN_HOLD_KEYS   = "$TEMP_DIR/broken.holds.txt";
my $CHANGED_HOLDS_LOG  = qq{changed_holds.log};
# These are our invalid locations which are gathered for your site automatically with getpol.
my @INVALID_LOCATIONS  = qw{};
my $UNIQ_ITEM_KEY_REF  = {};
my $CAT_KEYS_FIXCOUNTS = "$TEMP_DIR/sd_fixholds.keys";

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-a|-B<user_id>|-h<hold_key>|-H<hold_key_file>|-i<item_id_file>|-I<item_id>] -[cdrtUvVx]
	          [-f<non-hold-able_location>]
Item database errors occur on accounts when the customer has a hold, who's
hold key contains an item key that no longer exists. The script has
different modes of operation. If '-a' switch is used, the entire hold table
is searched for active holds that point to item keys that don't exist with
the following API.

 selhold -jACTIVE -oI 2>/dev/null | selitem -iI  2>$BROKEN_HOLD_KEYS

The script collects all the errors and parses the item keys before proceeding
to fix these items.

Another mode uses '-h' with a specific hold key. In this case the script
will find all the holds that are sitting on items that are in problematic
current locations. Once a hold on an invalid item has been identified, the
script will report the best item replacement.

A third mode allows the input of an item key file ('-i'), and will move holds from
a specific item to another viable item on the same title. This may not be possible
if there is only one item on the title, or all the other items are in non-existant
viable locations. See '-r' for more information.

Another common request is to fix holds on an item based on the item id. This
can be done with the '-I' flag.

Finally the '-B' switch will analyse the holds for a specific use and move the
holds that currently rest on non-viable items if possible. This may not be
possible if the hold is on a title with only one item, or all the items on
the title are non-viable (current locations are included in the list of
non-viable locations).

If the '-U' switch is used the hold will be updated without the customer
losing their place in the queue. If no viable item could be found to move
the hold to, the TCN and title will be reported to STDOUT if '-r' is selected,
otherwise the item key is printed to STDERR along with a message explaining
why the hold could not be moved.

Any holds that are moved are added to the $CHANGED_HOLDS_LOG file with the
following details
 HoldKey |CatKey |OriginalSeq|OriginalCopy|HoldStatus|Availability|
Example:
 26679727|1805778|2|1|ACTIVE|N|

 -a: Check entire hold table for holds with issues and report counts. The
     hold selection is based on ACTIVE holds that point to non-existant
     items. This does not report all holds that point to lost or stolen
     or discarded items. That would simply take too long.
 -B<user_id>: Input a specific user id, analyse.
 -c: Only consider moving holds to items that have the circulate flag set to 'Y'.
     Otherwise just consider items in hold-able locations.
 -d: Debug.
 -f<LOCATION>: Force a location to be recognized by this script to be unholdable.
     This will trigger the script to try and move these item holds to other
     hold-able locations.
     Normally this script checks policies for unhold-able location, but if you 
     want to include a sytem-recognized-holdable location as un-hold-able, then 
     include them with the -f flag.
     Example: -f"ON-ORDER,REF-BOOK"
     Now 'ON-ORDER', and 'REF-BOOK' will be considered un-hold-able in addition
     to the already sytem-recognized-holdable locations.
 -h<hold_key>: Input a specific hold key. This operation will look at all
     holds for the title that are placed on items that are currently in
     invalid locations like discard, missing, or stolen.
 -H<hold_key_file>: Moves holds from a specific hold keys listed
     in the argument file. See '-h' for similar operation. Hold keys
     should appear as the first non-white space data on each line, in pipe-
     delimited format. New lines are Unix style line endings. Example:
     '2101992|'
     '2101992|ocn2442309|Treasure Island|'
 -i<item_id_file>: Moves holds from a specific item keys listed
     in the argument file. See '-I' for similar operation. Item keys
     should appear as the first non-white space data on each line, in pipe-
     delimited format. New lines are Unix style line endings. Example:
     '12345|6|7|'
     '12345|66|7|ocn2442309|Treasure Island|'
 -I<item_barcode>: Moves holds from a specific item based on it's item ID if
     required, and if possible. This may not be possible if the only other items are in
     non-viable locations, or there is only one item on the title.
 -r: Prints TCNs and title of un-fixable holds to STDOUT. Each title reported uniquely.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Do the work, otherwise just print what would happen to STDERR. Runs SirsiDynix's
     fixholds on the cat keys that were identified to be fixed.
 -v: Verbose output.
 -V: Enforce the restriction of holds to the same call number.
 -x: This (help) message.

example:
  $0 -h26679728 -trU
  $0 -h26679728 -tr
  $0 -a
  $0 -aUr
  $0 -B21221012345678 -vU
  $0 -i"item.keys.lst" -vrU
  $0 -I31221116214003 -vrUt
  $0 -I31221116214003 -vrUtc
  $0 -I31221116214003 -vrUtc -fON-ORDER  # Consider ON-ORDER location as unholdable.
Cancel the holds, listed by hold key, in the argument file. Report if you can't do it, actually do it
if you can, and restrict to circulate-able items.
  $0 -H"hold.keys.lst" -rUc
Version: $VERSION
EOF
    exit;
}

# Removes all the temp files created during running of the script.
# param:  List of all the file names to clean up.
# return: <none>
sub clean_up
{
	foreach my $file ( @CLEAN_UP_FILE_LIST )
	{
		if ( $opt{'t'} )
		{
			printf STDERR "preserving file '%s' for review.\n", $file;
		}
		else
		{
			if ( -e $file )
			{
				unlink $file;
			}
			else
			{
				printf STDERR "** Warning: file '%s' not found.\n", $file;
			}
		}
	}
}

# Writes data to a temp file and returns the name of the file with path.
# param:  unique name of temp file, like master_list, or 'hold_keys'.
# param:  data to write to file.
# return: name of the file that contains the list.
sub create_tmp_file( $$ )
{
	my $name    = shift;
	my $results = shift;
	my $sequence= sprintf "%02d", scalar @CLEAN_UP_FILE_LIST;
	my $master_file = "$TEMP_DIR/$name.$sequence.$DATE.$TIME";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	open FH, ">$master_file" or die "*** error opening '$master_file', $!\n";
	print FH $results;
	close FH;
	# Add it to the list of files to clean if required at the end.
	push @CLEAN_UP_FILE_LIST, $master_file;
	return $master_file;
}

# Writes the contents of an array to file. For efficency sake we write a whole array
# at once. Otherwise an update is expensive when opening and closing the file.
# param:  file name string - path of file to write to.
# param:  table array reference - data to write to file (like: \@array_name).
# return: the number of items written to file.
sub writeTable( $$ )
{
	my $fileName = shift;
	my $table    = shift;
	open TABLE, ">$fileName" or die "Serialization error writing '$fileName' $!\n";
	foreach my $value ( @$table )
	{
		print TABLE "$value\n";
	}
	close TABLE;
	return scalar @$table;
}

# Returns the call number's analytical position which indicates the character position
# of the '|z' sub-field on the 099 entry. If the value is '0', there are no volumes.
# While this is how this is documented in Symphony, it doesn't work this way and there is no consistent way
# to identify true multi-volume titles as apposed to call nums that have '|z' or a non-
# zero analytical position.
# param:  String call number.
# return: 0 if there is no volumes on the title (the analytic position of '|z' sub-field
#         was not found), or a number > 0 otherwise.
sub is_volume_title( $ )
{
	my $call_number = shift;
	my $result = `echo "$call_number" | selitem -iN -oa 2>/dev/null | pipe.pl -oc0`;
	if ( ! $result )
	{
		printf STDERR "* warn, could not retrieve analytic position on call number '%s'\n", $call_number if ( $opt{'v'} || $opt{'d'} );
		return 0;
	}
	return $result;
}

# Gets a viable item id from all of the item ids on a title.
# param:  cat key of the offending item.
# param:  sequence number of the offending item.
# param:  copy number of the offending item.
# return: triple of new cat key, sequence number, and copy number of a good copy
#         from the title or an empty triple if none was found.
sub get_viable_itemKey( $$$ )
{
	my ( $ck, $sn, $cn ) = @_;
	my ( $newCK, $newSN, $newCN, $newLoc ) = "";
	# The cat key doesn't change - we use the same title - so save it now.
	$newCK = $ck;
	# Find all the items on the title. This may result in a list of anywhere from 1 - 'n' items.
	# If the result is 1, we have a problem because it is the original item, which is the one that
	# was causing the problem in the first place.
	# Added 'c' to check circulation flag in case we need it with '-c'.
	my $results = '';
	# Select based on call number. 
	# if ( $opt{'V'} or is_volume_title( "$ck|$sn|" ) )
	if ( $opt{'V'} )
	{
		$results = `echo "$ck|$sn|" | selitem -iN -oImu 2>/dev/null`;
	}
	else
	{
		$results = `echo "$ck" | selitem -iC -oImu 2>/dev/null`;
	}
	if ( $results )
	{
		my @resultLines = split '\n', $results;
		foreach my $line ( @resultLines )
		{
			my ( $k, $s, $c, $l, $circ ) = split '\|', $line;
			if ( grep( /^($l)$/, @INVALID_LOCATIONS ) )
			{
				printf STDERR "I fire grep : %s\n", $line if ( $opt{'d'} );
				next;
			}
			if ( $opt{'c'} && $circ !~ m/Y/ )
			{
				printf STDERR "I fire -c m/MN/ : %s\n", $line if ( $opt{'d'} );
				next;
			}
			else
			{
				printf STDERR "I fire: %s\n", $line if ( $opt{'d'} );
				( $newCK, $newSN, $newCN, $newLoc ) = split '\|', $line;
				last;
			}
		}
	}
	else
	{
		printf STDERR "** error, no additional items for cat key %s. Exiting.\n", $newCK;
	}
	# Note, these values could be empty if the location is found in the invalid location list.
	return ( $newCK, $newSN, $newCN, $newLoc ); # The new SN and new CN will be empty.
}

# Does the initial collection of all the hold keys that have problems. The selection
# is based on Symphony API:
#   selhold -jACTIVE -oI 2>/dev/null | selitem -iI  2>"$BROKEN_HOLD_KEYS" >/dev/null
# Where we collect all the error 111s and use the information in them. Note that in
# older releases of Symphony the item IDs are wrong but the cat key, sequence number
# and copy number can be used.
# param:  File name that contains the broken hold errors as in the example below.
#         **error number 111 on item start, cat=744637 seq=116 copy=1 id=31221113136142
# return: String - name of the file that contains the item keys.
sub collect_broken_holds( $ )
{
	my $err_file = shift;
	if ( ! -s $err_file )
	{
		return "";
	}
	# Sample output.
	# **error number 111 on item start, cat=744637 seq=116 copy=1 id=31221113136142
	# This finds the number of broken item keys.
	chomp( my $results = `cat "$err_file" | pipe.pl -g'c0:error' | wc -l` );
	$results = `echo "$results" | pipe.pl -tc0`;
	printf STDERR "Found %d hold error(s).\n", $results;
	# We need output to look like: '744637|116|1|'. The next line does this. Note that if you cut and paste this
	# line for testing remove the extra backslash in the last pipe.pl command. You need it if you run from a
	# script but not from the command line.
	$results = `cat "$err_file" | pipe.pl -W'=' -oc1,c2,c3 -h' ' | pipe.pl -W'\\s+' -zc0 -oc0,c2,c4 -P`;
	my $itemIdFile = create_tmp_file( "fixitemholdsbot_a_", $results );
	return $itemIdFile;
}

# Makes the changes to the call sequence and copy number.
# param:  Hold key to change.
# param:  valid call sequence number.
# param:  valid copy number.
# return: <none>
sub report_or_fix_callseq_copyno( $$$ )
{
	chomp( my $holdKey          = shift );
	chomp( my $viableSeqNumber  = shift );
	chomp( my $viableCopyNumber = shift );
	if ( ! $holdKey )
	{
		printf STDERR "** Warn: hold key empty.\n";
		return;
	}
	if ( $opt{'U'} )
	{
		# Now edit the hold to the new sequence number and copy number.
		# Note that edithold -c for sequence number and -d for copy number!
		`echo "$holdKey" | edithold -c"$viableSeqNumber"  2>/dev/null` if ( $viableSeqNumber );
		`echo "$holdKey" | edithold -d"$viableCopyNumber" 2>/dev/null` if ( $viableCopyNumber );
	}
	else # Just print out the results. This is to STDOUT so you can easily pipe to a script.
	{
		# Note that edithold -c for sequence number and -d for copy number!
		printf "echo \"%s\" | edithold -c\"%d\"\n", $holdKey, $viableSeqNumber if ( $opt{'v'} || $opt{'d'} );
		printf "echo \"%s\" | edithold -d\"%d\"\n", $holdKey, $viableCopyNumber if ( $opt{'v'} || $opt{'d'} );
	}
}

# Kicks off the setting of various switches.
# param:
# return:
sub init
{
    my $opt_string = 'aB:cdf:h:H:i:I:rtUvVx';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	# Dynamically populate the non-holdable locations from the system policies.
	my $results = `getpol -tLOCN | pipe.pl -gc3:N -oc2`;
	# Keep a copy in case someone asks to see what the script thinks is non-holdable.
	create_tmp_file( "fixitemholdsbot_sel_nonhold_loc_", $results );
	@INVALID_LOCATIONS = split '\n', $results;
	if ( $opt{'f'} )
	{
		my @additional_non_holdable_locations = split ',', $opt{'f'};
		foreach my $new_location ( @additional_non_holdable_locations )
		{
			push @INVALID_LOCATIONS, $new_location;
		}
	}
}

init();

### code starts
my $item_keys = '';
# Check the entire hold table.
if ( $opt{'a'} )
{
	# This line gets all the active holds in the hold table and give me the error 111 from selitem
	printf STDERR "Collecting hold information. This could take several minutes...\n";
	`selhold -jACTIVE -oI 2>/dev/null | selitem -iI 2>"$BROKEN_HOLD_KEYS" >/dev/null`;
	my $results = `cat $BROKEN_HOLD_KEYS`;
	my $err_file = create_tmp_file( "fixitemholdsbot_sel_opta_err_", $results );
	$item_keys = collect_broken_holds( $err_file );
}
elsif ( $opt{'h'} ) # Check a specific hold key.
{
	my $results = `echo "$opt{'h'}" | selhold -iK -oI 2>/dev/null`;
	if ( ! $results )
	{
		printf STDERR "** error invalid hold key '%s'.\n", $opt{'h'};
		exit( 0 );
	}
	$item_keys = create_tmp_file( "fixitemholdsbot_sel_opth_", $results );
}
elsif ( $opt{'B'} )
{
	# First test if the account is actually real.
	my $results = `echo "$opt{'B'}" | seluser -iB -oU 2>/dev/null`;
	my $user_key = "";
	if ( $results )
	{
		$user_key = create_tmp_file( "fixitemholdsbot_sel_optB_err_", $results );
	}
	else
	{
		printf STDERR "No such account %s.\n", $opt{'B'};
		exit( 0 );
	}
	$results = `cat $user_key | selhold -iU -jACTIVE -oIK 2>/dev/null | selitem -iI -oS 2> $opt{'B'}.err`;
	if ( -s "$opt{'B'}.err" )
	{
		# $opt{'B'}.err will contain if there is a problem.
		# **error number 111 on item start, cat=1805778 seq=3 copy=3 id=
		$results = `cat $opt{'B'}.err`;
		my $err_file = create_tmp_file( "fixitemholdsbot_B_err_", $results );
		$item_keys = collect_broken_holds( $err_file );
	}
	else
	{
		printf STDERR "No errors on account %s.\n", $opt{'B'};
		exit( 0 );
	}
}
elsif ( $opt{'H'} ) # Cancels holds by hold key file.
{
	# Check the user supplied a real non-empty file.
	if ( ! -s $opt{'H'} )
	{
		printf STDERR "** error invalid item key file '%s'.\n", $opt{'H'};
		exit( 0 );
	}
	# Get the item IDs from the hold keys, but make sure the holds are active and not available.
	my $results = `cat "$opt{'H'}" | selhold -iK -jACTIVE -aN -oI 2>/dev/null`;
	if ( ! $results )
	{
		printf STDERR "* Warn: no active available hold keys in '%s'.\n", $opt{'H'};
		exit( 0 );
	}
	$item_keys = create_tmp_file( "fixitemholdsbot_sel_optH_", $results );
}
elsif ( $opt{'i'} ) # Check a specific hold key.
{
	# Check the user supplied a real non-empty file.
	if ( ! -s $opt{'i'} )
	{
		printf STDERR "** error invalid item key file '%s'.\n", $opt{'i'};
		exit( 0 );
	}
	my $results = `cat "$opt{'i'}" | selitem -iI 2>/dev/null`;
	if ( ! $results )
	{
		printf STDERR "* Warn: no valid item IDs in '%s'.\n", $opt{'i'};
		exit( 0 );
	}
	$item_keys = create_tmp_file( "fixitemholdsbot_sel_opti_", $results );
}
elsif ( $opt{'I'} ) # Check a specific item ID.
{
	my $results = `echo "$opt{'I'}" | selitem -iB -oI 2>/dev/null`;
	if ( ! $results )
	{
		printf STDERR "** error invalid item bar code '%s'.\n", $opt{'I'};
		exit( 0 );
	}
	$item_keys = create_tmp_file( "fixitemholdsbot_sel_optI_", $results );
}
else # Neither required flag was supplied so report.
{
	printf STDERR "* warn, missing required flag missing. See below for more information.\n";
	usage();
}
if ( ! -s $item_keys )
{
	printf STDERR "No items to process.\n" if ( $opt{'v'} );
	exit( 0 );
}
# Open the $dedupItemIdFile file and use the cat key to get all the item keys.
# We will use the locations to determine viable copies and then choose the
# sequence number and copy number (if necessary) from a viable item with a reasonable location.
open ITEM_KEYS, "<$item_keys" || die "** error opening '$item_keys', $!.\n";
# Get an array ready for storing cat keys we need to fix.
my @cat_keys_to_fix = ();
while (<ITEM_KEYS>)
{
	chomp( my ( $catKey, $seqNumber, $copyNumber ) = split '\|', $_ );
	chomp( my $itemKey = $_ );
	my ( $viableItemKey, $viableSeqNumber, $viableCopyNumber, $viableLocation ) = get_viable_itemKey( $catKey, $seqNumber, $copyNumber );
	# So long as the viable seq #, and viable copy are not the same as the old ones and not empty then proceed.
	# We don't want to make changes unnecessarily
	if ( $viableSeqNumber && $viableCopyNumber )
	{
		if ( ( $viableSeqNumber != $seqNumber || $viableCopyNumber != $copyNumber ) )
		{
			# Now replace the old sequence with the new, and if required also the copy number.
			# Get the hold key.
			my $results = `echo "$catKey" | selhold -iC -c"$seqNumber" -d"$copyNumber" -oKIja 2>/dev/null`;
			# 21683010|1216974|4|3|ACTIVE|N|
			if ( $results )
			{
				my $holdsToFix = create_tmp_file( "fixitemholdsbot_$catKey", $results );
				`cat $holdsToFix >> $CHANGED_HOLDS_LOG`;
				chomp( my $holdKeyLines = `cat $holdsToFix | pipe.pl -oc0 -P` );
				my @holdKeys = split '\n', $holdKeyLines;
				foreach my $holdKey ( @holdKeys )
				{
					printf STDERR "Hold key: %s, item key '%s' should be changed to '%s|%s|%s|%s|'.\n", $holdKey, $itemKey, $viableItemKey, $viableSeqNumber, $viableCopyNumber, $viableLocation;
					report_or_fix_callseq_copyno( $holdKey, $viableSeqNumber, $viableCopyNumber );
				}
				# record cat keys to fix and them to a single file and at the end, 
				# with '-U' run them through fixholds.
				push @cat_keys_to_fix, $catKey if ( $opt{'U'} );
			}
			else # Couldn't find the hold key with explicit use of cat key sequence number and copy number.
			{
				printf STDERR "no hold found for item key '%s'!\n", $itemKey;
			}
		}
		else
		{
			printf STDERR "no change for item '%s', hold is on a valid item.\n", $itemKey;
		}
	}
	else
	{
		# Output unique title information, that is, only report once per title problem.
		$UNIQ_ITEM_KEY_REF->{ $itemKey } = 1;
	}
}
# Fix any cat key counts if -U.
if ( $opt{'U'} && scalar( @cat_keys_to_fix ) > 0 )
{
	my $count = writeTable( $CAT_KEYS_FIXCOUNTS, \@cat_keys_to_fix );
	printf STDERR "%d titles' hold counts will be updated...\n", $count;
	`cat "$CAT_KEYS_FIXCOUNTS" | fixholds -u 2>/dev/null`;
}
# Report what happened if necessary.
for my $key ( keys %$UNIQ_ITEM_KEY_REF ) 
{
	if ( $opt{'r'} )
	{
		chomp( my $tcn_title = `echo "$key" | selcatalog -iC -oFt 2>/dev/null` );
		printf "%s\n", $tcn_title if ( $tcn_title );
	}
	else
	{
		printf STDERR "* warning: item key '%s' has no viable sibling items.\n", $key;
	}
}
### code ends
clean_up();
# EOF
