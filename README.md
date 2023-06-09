# progress_tool

A short Ruby script I use for tracking my writing and revising progress.

To set up:

1. git clone locally
1. edit the file, change variables
  1. `target_file`
  1. `title`
  1. `target_words`
  1. `date_start`


To use:

1. write your story or novel in file `story.txt`
1. start each chapter with a string like "== chapter 1: intro"
1. to see your progress, run from the command line `rake`
1. to get an overview of your chapter sizes run `rake chapters`
1. once you're done with the first pass, begin revision.  Put the string "<==========" in your story file
1. ...and once you've done this, invocations of `rake` will generate new output, which has data on your REVISION
