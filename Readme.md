Project Notes
-------------
Initialized: Wed Nov 18 09:55:09 MST 2015.

Instructions for Running:
```
fixitemholdsbot.pl -x
```

Product Description:
--------------------
The script collects all the errors and parses the item keys before proceeding to fix these items.

The second mode uses '-h' with a specific hold key. In this case the script will find all the holds that are sitting on items that are in problematic current locations. Once a hold on an invalid item has been identified, the script will report the best item replacement. If the '-U' switch is used the hold will be updated without the customer losing their place in the queue. If no viable item could be found to move the hold to, the TCN and title will be reported to STDOUT if '-r' is selected, otherwise the item key is printed to STDERR along with a message explaining why the hold could not be moved.

Any holds that are moved are added to the changed_holds.log file with the following details.
```
HoldKey |CatKey |OriginalSeq|OriginalCopy|HoldStatus|Availability|
```
Example:
```
26679727|1805778|2|1|ACTIVE|N|
```


```
-a: Check entire hold table for holds with issues and report counts. The
    hold selection is based on ACTIVE holds that point to non-existant
        items. This does not report all holds that point to lost or stolen
    or discarded items. That would simply take too long.
-B<user_id>: Input a specific user id, analyse.
-h<hold_key>: Input a specific hold key. This operation will look at all
    holds for the title that are placed on items that are currently in
    invalid locations like discard, missing, or stolen.
-r: Prints TCNs and title of un-fixable holds to STDOUT.
-t: Preserve temporary files in /tmp.
-U: Do the work, otherwise just print what would do to STDERR.
-v: Verbose output.
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
