# JiraIssuesToTimeline
Jira issues converted to two different timeline formats and outputted to static html/js/css files. There is an overview format provided by Google Timelines and a more detailed view of individual issues/subtasks using TimelineJS. This formatting clears the clutter that is so prohibitive when viewing the history, activity, or transitions tabs in Jira. This is a work in progress.

##To install:
clone repo
add JiraIssuesToTimelin/lib to PERL5LIB

##To Run:

There are two modes

####Sprint Mode:

You pass the literal sprint name to the --sprint param.

perl ~/Scripts/Timeline/sprint_to_timeline.pl --username "username" --password "password" --sprint 'My Sprint' --start_date 2015 11 06 0 0 --end_date 2015 11 20 0 0

####Issue Mode:

Here you must pass a list of issues to the --issues param ( can be 1 long ) and a directory name to the --dir_name param.

perl ~/Scripts/Timeline/sprint_to_timeline.pl --username "username" --password "password" --issues 'KEY-1758' 'KEY-1456' --dir_name TEST2 --start_date 2015 11 06 0 0 --end_date 2015 11 20 0 0

end_date and start_date are optional params. They are used to scale the timelines to a certain scale. Events that occur after the end date or before the start date should be dropped from the timeline. Format is "yyyy mm dd hh mm".

The rest is pretty self-explanatory.

##To View:

Upload created directories to a webserver.
