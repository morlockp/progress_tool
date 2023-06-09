# progress_tool

A short Ruby script I use for tracking my writing and revising progress.

To set up:

# git clone locally
# edit the file, change variables
#* `target_file`
#* `title`
#* `target_words`
#* `date_start`


To use:

# write your story or novel in file `story.txt`
# start each chapter with a string like "== chapter 1: intro"
# to see your progress, run from the command line `rake`
# to get an overview of your chapter sizes run `rake chapters`
# once you're done with the first pass, begin revision.  Put the string "<==========" in your story file
# ...and once you've done this, invocations of `rake` will generate new output, which has data on your REVISION
