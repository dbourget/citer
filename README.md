# citer

A utility to inject citations from publication indexes into text files (latex, markdown). Currently, only the PhilPapers index is supported.

# Overview

This tool converts tags into citations. It supports search and ID tags.
Example search tag:

`This paper cites Bourget (@[consciousness intentionality]).`

When citer finds this, it will search PhilPapers for "bourget
consciousness intentionality" and inject a citation for the first match.
The item will be added to a bibliographic file. In latex mode (the only
mode that is fully supported at present), it will insert a \citeyear
command (customizable). 

Example ID tag:

`This paper cites Bourget (@BOUCIU).`

This works like the preceding but the paper will be found by PP ID. The PP
ids can be seen in the URL for the record pages, e.g.

`https://philpapers.org/rec/BOUCIU`

ID lookup is a backup for when there is a paper that you just can't get
to come up first by keyword search.

# Tips

Citer makes heavy use of caching in order to avoid hammering the
underlying index as you run and re-run and re-run it over the same text.
It caches both the search query results and the article metadata. It has
options (see help) to reset the cache if need be (say, if the metadata
have been updated in the index or new search results are available).
The caching isn't only to be nice: you need it to avoid being throttled.
PhilPapers currently limits API queries to 1000 per hour.

PhilPapers is an open access, wiki-like service. If you're not getting
the results you expect, perhaps you can contribute a fix to the index.

# Installation

There are some dependencies. First, you must install the Ruby
interpreter. Then you must install some "ruby gems" that are used by the
script. The included script install.sh should install the required
dependencies for you on mac or linux. Simply run

`sh install.sh`

You will be asked to provide your password in order to run the commands
as the superuser.


