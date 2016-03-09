Project Notes
-------------
Initialized: Wed Nov 18 09:55:09 MST 2015.

Instructions for Running:
```
fixitemholdsbot.pl -x
```

Product Description:
--------------------
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.
Used to audit broken holds, that is holds that point to invalid items that produce item database errors.

Item database errors occur on accounts when the customer has a hold, who's 
hold key contains an item key that no longer exists. We are not sure how 
this happens but suspect that demand management either selects an item 
that is then removed like a DISCARD, or fails to update items that have 
been discarded to valid item keys. No matter, fixing the issues requires 
finding the errant hold and changing it to point to an item in a valid 
current location.

First, using selhold, find all the ACTIVE holds that have invalid item keys.
Next, parse the error 111's and grab the cat key, sequence number, and copy 
number. You can't rely on the item id in these messages in older versions 
of Symphony.
Using the cat key, find another viable item on the title.
Finally with the cat key, sequence number, and copy number for a valid item
change the hold record to the valid ID.

 -c: Just check how many holds are we talking about.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Do the work, otherwise just print what would do to STDERR.
 -x: This (help) message.
 
Repository Information:
-----------------------
This product is under version control using Git.
[Visit GitHub](https://github.com/Edmonton-Public-Library)

Dependencies:
-------------
[Pipe.pl]{https://github.com/anisbet/pipe}

Known Issues:
-------------
None
