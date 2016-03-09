#!/usr/bin/perl -w
####################################################
#
# Perl source file for project deleteme 
# Purpose: Fix item database errors.
# Method:  Symphony API
#
# Audit and fix holds that point to invalid items resulting in item database errors.
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
#          0.1 - Production. 
#          0.0 - Dev. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################
my $VERSION            = qq{0.1};
my $TEMP_DIR           = `getpathname tmp`;
chomp $TEMP_DIR;
my $TIME               = `date +%H%M%S`;
chomp $TIME;
my $DATE               = `date +%m/%d/%Y`;
chomp $DATE;
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
my $BINCUSTOM          = `getpathname bincustom`;
chomp $BINCUSTOM;
my $PIPE               = "$BINCUSTOM/pipe.pl";

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
NON-ORDER
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

	usage: $0 [-xt]
Usage notes for $0.pl.

 -t: Preserve temporary files in $TEMP_DIR.
 -U: Do the work, otherwise just print what would do to STDERR.
 -x: This (help) message.

example:
  $0 -x
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
	my $master_file = "$TEMP_DIR/$name.$sequence.$TIME";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	open FH, ">$master_file" or die "*** error opening '$master_file', $!\n";
	print FH $results;
	close FH;
	# Add it to the list of files to clean if required at the end.
	push @CLEAN_UP_FILE_LIST, $master_file;
	return $master_file;
}

# Tests if an input of item id and location is a valid location according to the
# list of valid locations in the getpol -tLOCN tool.
# param:  line like '12345|1|2|CHECKEDOUT|'
# return: 1 if the location is valid and 0 otherwise.
sub isValidLocation( $ )
{
	# TODO: Finish me.
	my $catKeyLocation = shift;
	my @fields = split '\|', $catKeyLocation;
	if ( defined $fields[3] )
	{
		foreach my $location ( @INVALID_LOCATIONS )
		{
			return 0 if ( $fields[3] =~ m/($location)/ ); # if the item's location matches one of the forbidden locations return false.
		}
	}
	else
	{
		return 0;
	}
	return 1;
}

# Gets a viable item id from all of the item ids on a title. 
# param:  cat key
# param:  sequence number
# param:  copy number of the offending item.
# return: triple of new cat key, sequence number, and copy number of a good copy
#         from the title or an empty triple if none was found.
sub get_viable_itemKey( $$$ )
{
	my ( $ck, $sn, $cn ) = @_;
	my ( $newCK, $newSN, $newCN ) = "";
	$newCK = $ck;
	my $results = `echo "$ck" | selitem -iC -oIl 2>/dev/null`;
	my @resultLines = split '\n', $results;
	foreach my $line ( @resultLines )
	{
		if ( isValidLocation( $line ) )
		{
			( $newCK, $newSN, $newCN ) = split '\|', $line;
			last;
		}
	}
	return ( $newCK, $newSN, $newCN );
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'tUx';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
}

init();

### code starts
# Skip selection for testing if a list of broken items already exists. 
if ( $opt{'t'} and -s "broken.holds.txt" )
{
	printf STDERR "Test selected and 'broken.holds.txt' already exists; using that one.\n";
}
else # no way around it, got to make another.
{
	# This line gets all the active holds in the hold table and give me the error 111 from selitem
	`selhold -jACTIVE -oI | selitem -iI  2>broken.holds.txt >/dev/null`;
}

my $results = `cat broken.holds.txt | wc -l`;
chomp $results;
$results = `echo "$results" | "$PIPE" -tc0`;
printf "Found %d errors in hold table.\n", $results;
# Parse out the item keys. NOTE: you can't trust the item ID matches this item key.
# **error number 111 on item start, cat=614893 seq=40 copy=2 id=31221105766351
$results = `cat broken.holds.txt | "$PIPE" -W'=' -oc1,c2,c3 -h' ' | "$PIPE" -W'\\s+' -zc0 -oc0,c2,c4 -P`;
my $itemIdFile = create_tmp_file( "fixitemdb_", $results );
# Dedup on the item id.
$results = `cat "$itemIdFile" | "$PIPE" -d'c0,c1,c2' -P`;
my $dedupItemIdFile = create_tmp_file( "fixitemdb_", $results );
# TODO: Using the catalog key(s) find a valid item.
# Open the $dedupItemIdFile file and use the cat key to get all the item keys.
# We will use the locations to determine viable copies and then choose the 
# sequence number and copy number (if necessary) from a viable item with a reasonable location.
open ITEM_KEYS, "<$dedupItemIdFile" || die "** error opening '$dedupItemIdFile', $!.\n";
while (<ITEM_KEYS>)
{
	my ( $catKey, $seqNumber, $copyNumber ) = split '\|', $_;
	my ( $viableItemKey, $viableSeqNumber, $viableCopyNumber ) = get_viable_itemKey( $catKey, $seqNumber, $copyNumber );
	if ( $viableSeqNumber eq "" )
	{
		printf STDERR "* warning: no viable items on cat key '%s'.\n", $catKey;
		next;
	}
	# Now replace the old sequence with the new, and if required also the copy number.
	printf STDERR "item key '%s|%s|%s|'.\n", $viableItemKey, $viableSeqNumber, $viableCopyNumber;
	my $newItemId = sprintf "%s|%s|%s|", $viableItemKey, $viableSeqNumber, $viableCopyNumber;
	# Get a list of all the effected item ids for this title by sequence and copy number.
	$results = `echo "$catKey" | selhold -iC -c"$seqNumber" -d"$copyNumber" -oKIja`;
	# 21683010|1216974|4|3|ACTIVE|N|
	my $holdsToFix = create_tmp_file( "fixitemdb_$catKey", $results );
	if ( $opt{'U'} )
	{
		# Now edit the hold to the new sequence number and copy number.
		`cat "$holdsToFix" | edithold -c"$viableSeqNumber"` if ( $viableSeqNumber != $seqNumber );
		`cat "$holdsToFix" | edithold -d"$viableCopyNumber"` if ( $viableCopyNumber != $copyNumber );
	}
	else
	{
		printf STDERR "cat \"%s\" | edithold -c\"%s\"\n", $holdsToFix, $viableSeqNumber;
		printf STDERR "cat \"%s\" | edithold -d\"%s\"\n", $holdsToFix, $viableCopyNumber;
	}
}
### code ends
if ( $opt{'t'} )
{
	printf STDERR "Temp files will not be deleted. Please clean up '%s' when done.\n", $TEMP_DIR;
}
else
{
	clean_up();
}
# EOF
