Project Notes
-------------
Initialized: Wed Nov 18 09:55:09 MST 2015.

Instructions for Running:
```
fixitemholdsbot.pl -x
```

Product Description:
--------------------
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

Any holds that are moved are added to the changed_holds.log file with the following details.
```
HoldKey |CatKey |OriginalSeq|OriginalCopy|HoldStatus|Availability|
```
Example:
```
26679727|1805778|2|1|ACTIVE|N|
```
Generally this script assumes that viable holds can be found under any call
number but -V restricts the selection to the same call number; volume holds.

```
 -c: Only consider moving holds to items that have the circulate flag set to 'Y'.
     Otherwise just consider items in hold-able locations. 
 -d: Debug.
 -a: Check entire hold table for holds with issues and report counts. The 
     hold selection is based on ACTIVE holds that point to non-existant 
     items. This does not report all holds that point to lost or stolen
     or discarded items. That would simply take too long.
 -B<user_id>: Input a specific user id, analyse.
 -h<hold_key>: Input a specific hold key. This operation will look at all
     holds for the title that are placed on items that are currently in 
     invalid locations like discard, missing, or stolen.
 -i<item_id_file>: Moves holds from a specific item keys listed
     in the argument file. See '-I' for similar operation. Item keys
     should appear as the first non-white space data on each line, in pipe-
     delimited format. New lines are Unix style line endings. Example: 
     '12345|6|7|'
     '12345|66|7|ocn2442309|Treasure Island|'
 -I<item_barcode>: Moves holds from a specific item based on it's item ID if
     required, and if possible. This may not be possible if the only other items are in
     non-viable locations, or there is only one item on the title.
 -r: Prints TCNs and title of un-fixable holds to STDOUT.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Do the work, otherwise just print what would do to STDERR.
 -v: Verbose output.
 -V: Assume volume holds, restrict holds to the same call number.
 -x: This (help) message.
```
 
Repository Information:
-----------------------
This product is under version control using Git.
[Visit GitHub](https://github.com/Edmonton-Public-Library)

Dependencies:
-------------
[Pipe.pl](https://github.com/anisbet/pipe)

Known Issues:
-------------
None
