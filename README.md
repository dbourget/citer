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


# Full usage example

Currently, the best tested use case is to insert latex citations within
a MultiMarkDown document (which is what the author currently needs; the MMD document is later converted to latex).
This can be done like this:

`ruby citer.rb -i output.md -o withcites.md -b refs.bib -f bibtex -x extra.bib -e `

"-i" is the input file. "-o" is the output file. "-b" is the output file
for the generated bibliography, which is always in bibtex. "-f" is the
in-text citation format. Currently only bibtex is fully supported. This
means inserting \citeyear (another command can be specified using another argument). "-x" is to provide an existing bibliography that will be added to the output bibliography. This is useful for things that cannot be inserted by citer. "-e" specifies that the inserted bibtex should be escaped for latex embedding within markdown.

This is untested, but in principle the tool should be usable with
regular latex files as follows:

`ruby citer.rb -i yourfile.tex -o withcites.tex -b refs.bib -f bibtex`

# Installation

There are some dependencies. First, you must install the Ruby
interpreter. Then you must install some "ruby gems" that are used by the
script. The included script install.sh should install the required
dependencies for you on mac or linux. Simply run

`sh install.sh`

You will be asked to provide your password in order to run the commands
as the superuser.

In addition, you will need to create the configuration file. It should
be located in your home directory and called *.citer-config.yaml* (don't
forget the dot at the beginning). It should have this format:

`
apiId: [your api id; see below]
apiKey: [your api key]
cacheRoot: [where you want the cache]
`

The cache location should not be volatile (so not /tmp). Your home directory is just
fine. It is configurable because it can be convenient to put it on
Dropbox or similar---running citer on a lot of citations can be very
slow because it throttles queries to 1 per second.

# PhilPapers API 

In order to obtain a PhilPapers API key, you will need to create a user
account. Then visit this page:

[https://philpapers.org/utils/create_api_user.html]


