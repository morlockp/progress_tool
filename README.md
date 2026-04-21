# progress_tool

A short Ruby script I use for tracking my writing and revising progress.

To set up:

1. git clone this repo
1. create a new directory for your writing project
1. in that directory, start your your story or novel in file named `story.txt`
1. in that directory, run `rake init` ; this creates a file `.rakefile.yaml`.  
1. start each chapter with a string like "* chapter 1: intro"
1. customize the `rakefile.yaml` as you see fit.  You can change target words, start date, chapter headings, etc.  

Configuration meanings:

- :target_file: what file holds the story?
- :title: what story title should be reported in the statistics?
- :target_words: how long you expect the story to be
- :date_start: the date you started working on the project
- :chapter_head_tag: a string that marks the begining of each chapter
- :size_cuttoff_chapter: a number of words under which the script can conclude the chapter is incomplete
- :size_cutoff_force_done: an optional string that tells the script that an overly short (see line above) chapter is actually complete
- :size_cutoff_force_incomplete: an optional string that tells the script that an overly long chapter should still be treated as incomplete

## Multi-file Interleaving with Pragmas

When using multiple input files (plot threads), you can enforce ordering constraints using pragmas:

### Defining and Requiring Tags

In any chapter, add pragmas as comments:

```
** chapter 5: The Setup
# DEFINE-TAG: lopez-turning-point

Content of the chapter...
```

In another file's chapter, require that tag:

```
** chapter 8: The Convergence
# MUST-BE-AFTER: lopez-turning-point

Content of the chapter...
```

You can also specify that a chapter must come before another:

```
** chapter 3: Early Conflict
# MUST-BE-BEFORE: lopez-turning-point

Content of the chapter...
```

N.B. the pound signs are mandatory

### Multiple Dependencies

A single chapter can depend on multiple tags:

```
** chapter 12: The Finale
# MUST-BE-AFTER: lopez-turning-point, mackenzie-revelation

Content...
```

### Validation

The interleave tasks will:
- ✅ Enforce ordering: chapters with dependencies appear after their required tags
- ✅ Detect undefined tags: error if a tag is required but never defined
- ✅ Detect circular dependencies: error if tags form a cycle
- ⚠️ Warn on unused tags: tags defined but never required

If constraints are impossible to satisfy or invalid, the task will abort with a clear error message.

## To use on your first (writing) pass

1. to see a compact view progress stats, run from the command line `rake`
1. to get an overview of your chapter sizes run `rake chapters`

N.B. that if you change text

> Tom said wryly

to

> Tom said innocently

that this should be appear in the statistics as

 today's word delta: +0   (+1 -1)

Note two minor features:

1. you can sprinkle "XXX", "YYY", and "ZZZ" throughout your story file ; these tag open issues of various types (the tool does not define what these issue types are; you can use "XXX"  for "add more details here", "YYY" for "problem w the timeline, etc.).  If one or more of these is present, `rake` stats will refer to these.
1. you can create a file `unused_text.txt` and move chunks of stuff from your story file to here.  This way you "get credit" for writing stuff, even if you end up not using it in your draft.

Use this process until you finish writing the first draft of your story.

After that you will likely want to edit your story, so ...

## To use on a revision pass

1. Begin revising at the top of oyur story. 
1. Put the string "<---" in your story file to mark how far you've progressed in revising.
1. Having done this, invocations of `rake` and `rake chapters` will generate expanded output

## To contribute

After making changes, please run `rake self_test`.

Thanks!
