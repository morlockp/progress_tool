# progress_tool

A short Ruby script I use for tracking my writing and revising progress.

To set up:

1. git clone this repo
1. create a new directory for your writing project
1. in that directory, start your your story or novel in file named `story.txt`
1. in that directory, run `rake init` ; this creates a file `.rakefile.yaml`.  
1. start each chapter with a string like "* chapter 1: intro"
1. customize the `rakefile.yaml` as you see fit.  You can change target words, start date, chapter headings, etc.

To use on your first (writing) pass:

1. to see a compact view progress stats, run from the command line `rake`
1. to get an overview of your chapter sizes run `rake chapters`

To use on a revision pass:

1. Put the string "<---" in your story file to mark how far you've progressed in revising.
1. Having done this, invocations of `rake` and `rake chapters` will generate expanded output

