#!/usr/bin/perl -w
###################################################################
#
# Perl source file for project deleteme 
# Purpose: Fix item database errors.
# Method:  Symphony API
#
# Audit and fix holds that point to invalid items resulting in item 
# database errors.
#    Copyright (C) 2015  Andrew Nisbet
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
# Created: Thu Nov 19 14:26:00 MST 2015
# Rev: 
#          0.1.04 - Added -r, -i for hold key, refactored and tested. 
#          0.1.02 - Added temp file path to broken holds. 
#          0.1.01 - Fix hold count error reporting. 
#          0.1 - Production. 
#          0.0 - Dev. 
# Dependencies: pipe.pl, selhold, selitem, getpathname.
#
###################################################################

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
my $VERSION            = qq{0.1.04};
chomp( my $TEMP_DIR    = `getpathname tmp` );
chomp( my $TIME        = `date +%H%M%S` );
chomp( my $DATE        = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
chomp( my $BINCUSTOM   = `getpathname bincustom` );
my $BROKEN_HOLD_KEYS   = "$TEMP_DIR/broken.holds.txt";
my $CHANGED_HOLDS_LOG  = qq{changed_holds.log};
# These are our invalid locations, your's willl vary. Use getpol to find invalid locations at your site.
my @INVALID_LOCATIONS  = qw{
UNKNOWN 
REFERENCE
MISSING
LOST
BINDERY
INPROCESS
DISCARD
ILL
RESERVES
CATALOGING
LOST-PAID
REPAIR
AVCOLL
CANC_ORDER
DISPLAY
EPLBINDERY
EPLCATALOG
EPLILL
GOVPUB
FLICKTUNE
INCOMPLETE
INDEX
INTERNET
STORAGE
STORAGEHER
STORAGEREF
DAMAGE
BARCGRAVE
ON-ORDER
CANC_ORDER
NON-ORDER
REF-ORDER
LOST-ASSUM
LOST-CLAIM
PROGRAM
BESTSELLER
REF-ORDER
JBESTSELLR
STORAGEGOV
INSHIPPING
STOLEN
NOF
MAKER};

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-a|-i<hold_key>] {rtUx]
Item database errors occur on accounts when the customer has a hold, who's 
hold key contains an item key that no longer exists. The script has 2
different modes of operation. If '-a' switch is used, the entire hold table
is searched for active holds that point to item keys that don't exist with
the following API.

 selhold -jACTIVE -oI 2>/dev/null | selitem -iI  2>$BROKEN_HOLD_KEYS 
 
The script collects all the errors and parses the item keys before proceeding
to fix these items.

The second mode uses '-i' with a specific hold key. In this case the script
will find all the holds that are sitting on items that are in problematic 
current locations. Once a hold on an invalid item has been identified, the
script will report the best item replacement. If the '-U' switch is used 
the hold will be updated without the customer losing their place in the queue.
If no viable item could be found to move the hold to, the TCN and title will
be reported to STDOUT if '-r' is selected, otherwise the item key is printed
to STDERR along with a message explaining why the hold could not be moved.

Any holds that are moved are added to the $CHANGED_HOLDS_LOG file with the
following details
 HoldKey |CatKey |Seq|Copy|HoldStatus|Available|
Example:
 26679727|1805778|2|1|ACTIVE|N|

 -a: Check entire hold table for holds with issues and report counts. The 
     hold selection is based on ACTIVE holds that point to non-existant 
	 items. This does not report all holds that point to lost or stolen
     or discarded items. That would simply take too long.
 -i<hold_key>: Input a specific hold key. This operation will look at all
     holds for the title that are placed on items that are currently in 
     invalid locations like discard, missing, or stolen.
 -r: Prints TCNs and title of un-fixable holds to STDOUT.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Do the work, otherwise just print what would do to STDERR.
 -x: This (help) message.

example:
  $0 -i26679728 -trU
  $0 -i26679728 -tr
  $0 -a
  $0 -aUr
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

# Gets a viable item id from all of the item ids on a title. 
# param:  cat key of the offending item.
# param:  sequence number of the offending item.
# param:  copy number of the offending item.
# return: triple of new cat key, sequence number, and copy number of a good copy
#         from the title or an empty triple if none was found.
sub get_viable_itemKey( $$$ )
{
	my ( $ck, $sn, $cn ) = @_;
	my ( $newCK, $newSN, $newCN ) = "";
	# The cat key doesn't change - we use the same title - so save it now.
	$newCK = $ck;
	# Find all the items on the title. This may result in a list of anywhere from 1 - 'n' items.
	# If the result is 1, we have a problem because it is the original item, which is the one that
	# was causing the problem in the first place.
	my $results = `echo "$ck" | selitem -iC -oIm 2>/dev/null`;
	if ( $results )
	{
		my @resultLines = split '\n', $results;
		foreach my $line ( @resultLines )
		{
			my ( $k, $s, $c, $l ) = split '\|', $line;
			if ( ! grep( /($l)/, @INVALID_LOCATIONS ) )
			{
				( $newCK, $newSN, $newCN ) = split '\|', $line;
				last;
			}
		}
	}
	else
	{
		printf STDERR "** error, no additional items for cat key %s. Exiting.\n", $newCK;
	}
	# Note, these values could be empty if the location is found in the invalid location list.
	return ( $newCK, $newSN, $newCN ); # The new SN and new CN will be empty.
}

# Does the initial collection of all the hold keys that have problems. The selection
# is based on Symphony API: 
#   selhold -jACTIVE -oI 2>/dev/null | selitem -iI  2>"$BROKEN_HOLD_KEYS" >/dev/null
# Where we collect all the error 111s and use the information in them. Note that in 
# older releases of Symphony the item IDs are wrong but the cat key, sequence number
# and copy number can be used.
# param:  <none>
# return: String - name of the file that contains the item keys.
sub collect_broken_holds()
{
	# This line gets all the active holds in the hold table and give me the error 111 from selitem
	printf STDERR "Collecting hold information. This could take several minutes...\n";
	`selhold -jACTIVE -oI 2>/dev/null | selitem -iI  2>"$BROKEN_HOLD_KEYS" >/dev/null`;
	# Sample output.
	# **error number 111 on item start, cat=744637 seq=116 copy=1 id=31221113136142
	# This finds the number of broken item keys.
	chomp( my $results = `cat "$BROKEN_HOLD_KEYS" | pipe.pl -g'c0:error' | wc -l` );
	$results = `echo "$results" | pipe.pl -tc0`;
	printf STDERR "Found %d holds for invalid items in hold table.\n", $results;
	# We need output to look like: '744637|116|1|'. The next line does this. Note that if you cut and paste this 
	# line for testing remove the extra backslash in the last pipe.pl command. You need it if you run from a 
	# script but not from the command line.
	$results = `cat "$BROKEN_HOLD_KEYS" | pipe.pl -W'=' -oc1,c2,c3 -h' ' | pipe.pl -W'\\s+' -zc0 -oc0,c2,c4 -P`;
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
		printf "echo \"%s\" | edithold -c\"%s\"\n", $holdKey, $viableSeqNumber;
		printf "echo \"%s\" | edithold -d\"%s\"\n", $holdKey, $viableCopyNumber;
	}
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'ai:rtUx';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
}

init();

### code starts
my $item_keys = '';
# Check the entire hold table.
if ( $opt{'a'} )
{
	$item_keys = collect_broken_holds();
	exit( 0 );
}
elsif ( $opt{'i'} ) # Check a specific hold key.
{
	my $results = `echo "$opt{'i'}" | selhold -iK -oI 2>/dev/null`;
	if ( ! $results )
	{
		printf STDERR "** error invalid hold key '%s'.\n", $opt{'i'};
		exit( 0 );
	}
	$item_keys = create_tmp_file( "fixitemholdsbot_sel_opti", $results );
}
else # Neither required flag was supplied so report.
{
	printf STDERR "* warn, you must supply a hold key with -i or use -a to test the entire hold table.\n";
	usage();
}
if ( ! -s $item_keys )
{
	printf STDERR "No items to process.\n";
	exit( 0 );
}
# Open the $dedupItemIdFile file and use the cat key to get all the item keys.
# We will use the locations to determine viable copies and then choose the 
# sequence number and copy number (if necessary) from a viable item with a reasonable location.
open ITEM_KEYS, "<$item_keys" || die "** error opening '$item_keys', $!.\n";
while (<ITEM_KEYS>)
{
	chomp( my ( $catKey, $seqNumber, $copyNumber ) = split '\|', $_ );
	chomp( my $itemKey = $_ );
	my ( $viableItemKey, $viableSeqNumber, $viableCopyNumber ) = get_viable_itemKey( $catKey, $seqNumber, $copyNumber );
	# So long as the viable seq #, and viable copy are not the same as the old ones and not empty then proceed.
	# We don't want to make changes unnecessarily 
	if ( $viableSeqNumber && $viableCopyNumber )
	{
		if ( ( $viableSeqNumber != $seqNumber || $viableCopyNumber != $copyNumber ) )
		{
			# Now replace the old sequence with the new, and if required also the copy number.
			printf "item key '$itemKey' should be changed to '%s|%s|%s|'.\n", $viableItemKey, $viableSeqNumber, $viableCopyNumber;
			# Get the hold key.
			my $results = `echo "$catKey" | selhold -iC -c"$seqNumber" -d"$copyNumber" -oKIja 2>/dev/null`;
			# 21683010|1216974|4|3|ACTIVE|N|
			if ( $results )
			{
				my $holdsToFix = create_tmp_file( "fixitemholdsbot_$catKey", $results );
				`cat $holdsToFix >> $CHANGED_HOLDS_LOG`;
				my $holdKey = `cat $holdsToFix | pipe.pl -oc0 -P`;
				report_or_fix_callseq_copyno( $holdKey, $viableSeqNumber, $viableCopyNumber );
			}
		}
		else
		{
			printf STDERR "no change for item '%s', hold is on a valid item.\n", $itemKey;
		}
	}
	else
	{
		if ( $opt{'r'} )
		{
			printf `echo "$itemKey" | selcatalog -iC -oFt 2>/dev/null`;
		}
		else
		{
			printf STDERR "* warning: item key '%s' has no viable items.\n", $itemKey;
		}
	}
}
### code ends
clean_up();
# EOF
