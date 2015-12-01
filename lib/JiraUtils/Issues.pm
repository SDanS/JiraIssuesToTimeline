package JiraUtils::Issues;

use strict;
use warnings;

no warnings 'uninitialized';

use Carp;
use REST::Client;
use JSON;

use parent qw(JiraUtils);

sub new {
    my $class = shift;
    my ( $username, $password ) = @_;

    my $self = $class->SUPER::new( $username, $password );
    return $self;
}

### Request a single issue. Returns a huge json object.
sub issue_request {
    my $self         = shift;
    my $request_type = shift;
    my $expand       = shift;
    my $req_expand   = '?expand=' . $expand if $expand;
    if ( $request_type eq "get" ) {
        $self->{client}
            ->GET( '/rest/api/2/issue/' . $self->{issue_key} . $req_expand,
            $self->{auth_headers} )
            or croak 'Could not retrieve issue.';
        $self->{jiraIssue} = from_json( $self->{client}->responseContent() )
            or croak 'Response content is not json.';
    }
    return $self;
}

### Get meaningful bits from response and organize them a little better.
sub buckets {
    my $self          = shift;
    my $history_items = shift;
    my ( $start_date, $start_datetime, $end_date, $end_datetime ) = @_;
    $self->{buckets} = {};
    my $histories = $self->{jiraIssue}->{changelog}->{histories};
    foreach (@$history_items) {
        $self->{buckets}->{$_} = [];
    }
    foreach my $history_index ( 0 .. $#{$histories} ) {
        foreach my $item_index (
            0 .. $#{ $histories->[$history_index]->{items} } )
        {
            if (my ($bucket) = grep {
                    $_ eq $histories->[$history_index]->{items}->[$item_index]
                        ->{field}
                } @$history_items
                )
            {
                push @{ $self->{buckets}->{$bucket} },
                    $histories->[$history_index];
                next;
            }
        }
    }
    $self->{summary} = $self->{jiraIssue}->{fields}->{summary};
    $self->title();
    $self->comments_into_bucket()
        if ( grep { "comments" eq $_ } @$history_items );
    ### Process subtasks
    $self->subtask_builder(
        $self->{issue_key}, $start_date, $start_datetime,
        $end_date,          $end_datetime
    ) if defined $self->{jiraIssue}->{fields}->{subtasks};
    return $self;
}

### Get the title and save it for later.
sub title {
    my $self = shift;
    $self->{timeline_href}->{title}->{text}->{headline}
        = "<a href=\"https://jira.cpanel.net/browse/$self->{issue_key}\">$self->{issue_key}: "
        . $self->{summary} . '</a>';
    $self->{timeline_href}->{issue_key} = $self->{issue_key};
    return $self;
}

### Put the comments in a bucket.
sub comments_into_bucket {
    my $self = shift;
    $self->{buckets}->{comments}
        = $self->{jiraIssue}->{fields}->{comment}->{comments};
    return $self;
}

### Iterate over a story's subtasks and process them.
sub subtask_builder {
    my $self   = shift;
    my $parent = shift;
    my ( $start_date, $start_datetime, $end_date, $end_datetime ) = @_;
    foreach ( @{ $self->{jiraIssue}->{fields}->{subtasks} } ) {
        my $subtask = JiraUtils::Issues->new();
        $subtask->{client}       = $self->{client};
        $subtask->{auth_headers} = $self->{auth_headers};
        $subtask->{issue_key}    = $_->{key};
        $subtask->issue_request( 'get', 'changelog' );
        my $buckets = [
            'summary', 'description', 'priority', 'issuetype',
            'status',  'Sprint',      'assignee', 'comments',
            'Story Points'
        ];
        $subtask->buckets( $buckets, );
        $subtask->span_tile_events( $start_date, $start_datetime, $end_date,
            $end_datetime );
        $subtask->scope_events( $start_date, $start_datetime, $end_date,
            $end_datetime );
        $subtask->comment_events( $start_date, $start_datetime, $end_date,
            $end_datetime );
        $subtask->{timeline_href}->{parent} = $parent;
        push @{ $self->{timeline_href}->{subtasks} },
            $subtask->{timeline_href};
    }
    return $self;
}

### Process status and assignment events into spans for TimelineJS.
sub span_tile_events {
    my $self = shift;
    my ($terminal_start_date, $terminal_start_datetime,
        $terminal_end_date,   $terminal_end_datetime
    ) = @_;
    $self->{timeline_href}->{events} = [];
    foreach my $current_bucket ( 'assignee', 'status' ) {
        foreach ( 0 .. $#{ $self->{buckets}->{$current_bucket} } ) {
            my $bucket_instance = $self->{buckets}->{$current_bucket}->[$_];
            my $next_bucket_instance
                = $self->{buckets}->{$current_bucket}->[ $_ + 1 ];
            my $text = my $event->{text} = {};
            my ( $start_date, $start_datetime )
                = _timeline_time( $bucket_instance->{created} );
            $event->{start_date}     = $start_date;
            $event->{start_datetime} = $start_datetime;
            my $cmp = DateTime->compare( $event->{start_datetime},
                $terminal_start_datetime );
            if ( $cmp == -1 ) {
                $event->{start_date}     = $terminal_start_date;
                $event->{start_datetime} = $terminal_start_datetime;
            }
            if ( $_ != $#{ $self->{buckets}->{$current_bucket} } ) {
                my ( $end_date, $end_datetime )
                    = _timeline_time( $next_bucket_instance->{created} );
                $event->{end_date}     = $end_date;
                $event->{end_datetime} = $end_datetime;
                my $cmp = DateTime->compare( $event->{end_datetime},
                    $terminal_end_datetime );
                if ( $cmp == 1 ) {
                    $event->{end_date}     = $terminal_end_date;
                    $event->{end_datetime} = $terminal_end_datetime;
                }
            }
            if ( !$event->{end_date} ) {
                $event->{end_date} = $terminal_end_date;
            }
            foreach ( @{ $bucket_instance->{items} } ) {
                if ( $_->{field} eq $current_bucket ) {
                    my $to_string   = $_->{toString}   // 'unassigned';
                    my $from_string = $_->{fromString} // 'unassigned';
                    $text->{headline} = "Assignee: " . $to_string
                        if $_->{field} eq 'assignee';
                    $text->{headline} = $to_string if $_->{field} eq 'status';
                    $text->{text}
                        = ucfirst( $_->{field} )
                        . ' changed from '
                        . $from_string . ' to '
                        . $to_string;
                    $event->{group} = $_->{field};
                    status_colors( $event, $_ )
                        if $_->{field} eq 'status';
                    $event->{background}->{color} = 'seagreen'
                        if $_->{field} eq 'assignee';
                }
                else {
                    next;
                }
                my $cmp = DateTime->compare( $event->{end_datetime},
                    $event->{start_datetime} )
                    if ( $event->{end_datetime} && $event->{start_datetime} );
                if ( $cmp != -1 ) {
                    push @{ $self->{timeline_href}->{events} }, $event;
                }
            }
        }
    }
    return $self;
}

### Process scope events for TimelineJS.
sub scope_events {
    my $self = shift;
    my ($terminal_start_date, $terminal_start_datetime,
        $terminal_end_date,   $terminal_end_datetime
    ) = @_;
    my $scope = [ 'summary', 'description', 'Story Points' ];
    my $misc = [ 'priority', 'issuetype' ];
    foreach my $bucket_key ( @$scope, @$misc ) {
        my $current_bucket = $self->{buckets}->{$bucket_key};
        foreach my $bucket_instance ( @{$current_bucket} ) {
            my $event = {};
            my ( $start_date, $start_datetime )
                = _timeline_time( $bucket_instance->{created} );
            $event->{start_date}     = $start_date;
            $event->{start_datetime} = $start_datetime;
            foreach my $item ( @{ $bucket_instance->{items} } ) {
                my $field = $item->{field};
                if ( grep { $_ eq $field } @$scope ) {
                    $event = { %$event, 'group' => 'scope', };
                    $event->{background}->{color} = 'palevioletred';
                }
                elsif ( grep { $_ eq $field } @$misc ) {
                    $event = { %$event, 'group' => 'misc', };
                    $event->{background}->{color} = 'plum';
                }
                else { next; }
                my $from_string = $item->{fromString} // 'undef';
                $event->{text}->{text}
                    = ucfirst($field)
                    . ' changed from: <br>'
                    . $from_string
                    . '<br><br>To: <br>'
                    . $item->{toString};
                $event->{text}->{headline} = ucfirst($field) . ' changed.';
                push @{ $self->{timeline_href}->{events} }, $event;

            }
        }
    }
    return $self;
}

### Process comment events for TimelineJS
sub comment_events {
    my $self = shift;
    my ($terminal_start_date, $terminal_start_datetime,
        $terminal_end_date,   $terminal_end_datetime
    ) = @_;
    foreach ( @{ $self->{buckets}->{comments} } ) {
        my $event = {};
        my ( $start_date, $start_datetime ) = _timeline_time( $_->{created} );
        $event->{start_date}          = $start_date;
        $event->{start_datetime}      = $start_datetime;
        $event->{group}               = 'misc';
        $event->{background}->{color} = 'olivedrab';
        $event->{text}->{headline}
            = 'Comment added by ' . $_->{author}->{displayName};

        $event->{text}->{text} = $_->{body};
        $event->{text}->{text} =~ s/\r\n/<br>/g;
        $event->{text}->{text} =~ s/\{noformat\}//g;
        push @{ $self->{timeline_href}->{events} }, $event;
    }
    return $self;
}

### Set status colors for slide backgrounds.
sub status_colors {
    my $event      = shift;
    my $item       = shift;
    my $color_href = {
        'To Do'         => 'gray',
        'In Progress'   => 'darkcyan',
        'In Review'     => 'dodgerblue',
        'In Test'       => 'darkblue',
        'Merge Pending' => 'slateblue',
        'Done'          => 'indigo'
    };
    for ( keys $color_href ) {
        $event->{background}->{color} = $color_href->{ $item->{toString} };
    }
}

### Deal with Jira's wacky time.
sub _timeline_time {
    my $time     = shift;
    my $datetime = JiraUtils::dt_iso_8601($time);
    my $date     = {};
    $date->{month}  = $datetime->month;
    $date->{day}    = $datetime->day;
    $date->{year}   = $datetime->year;
    $date->{hour}   = $datetime->hour;
    $date->{minute} = $datetime->min;
    return $date, $datetime;
}

### Create the directory for an issue which may have subtasks.
sub issue_dir {
    my $self = shift;
    unless ( mkdir "./$self->{issue_key}" ) {
        croak "Unable to create $self->{issue_key}: $!";
    }
    return $self;
}

### Write out the javascript for story TimelineJS
sub write_json {
    my $self = shift;
    my $fh_color;
    open my $fh, '>', "./$self->{issue_key}/$self->{issue_key}.json"
        or croak("Cannot open filehandle $self->{issue_key}: $!\n");
    print $fh "var timeline_json = "
        . to_json( $self->{'timeline_href'},
        { pretty => 1, allow_blessed => 1 } )
        or croak("Cannot print to $self->{key}: $!");
    $self->write_subtask_json()
        if defined $self->{timeline_href}->{subtasks};
### This should be moved to Sprint.pm
    $self->colors_js();
    open $fh_color, '>', "./$self->{issue_key}/color.js"
        or croak "Cannot open filehandle: $fh_color";
    print $fh_color $self->{color_js_text}
        or croak "Cannot print to file: $fh_color";
    return $self;
}

### Write out the javascript for subtask TimelineJS
sub write_subtask_json {
    my $self = shift;
    foreach ( @{ $self->{timeline_href}->{subtasks} } ) {
        open my $fh, ">", "./$_->{parent}/$_->{issue_key}.json"
            or croak("Cannot open filehandle $_->{issue_key}: $!\n");
        print $fh "var timeline_json = "
            . to_json( $_, { pretty => 1, allow_blessed => 1 } )
            or
            croak("Cannot print to $_->{parent}\/$_->{issue_key}.json: $!\n");
    }
    return $self;
}

### Write the html for TimelineJS
### Convert to qq{};
sub write_html {
    my $self = shift;
    (   my $options = qq[
            {
                initial_zoom: 1,
                timenav_height_percentage: 35
            }
            ]
    ) =~ s/ {4,8,12}//mg;
    ( my $html = <<"    HTML") =~ s/^ {8}//gm;
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        </head>
        <title>$self->{issue_key}: Timeline</title>
        <head></head>
        <body>
            <!-- 1 -->
            <link title="timeline-styles" rel="stylesheet" href="//cdn.knightlab.com/libs/timeline3/latest/css/timeline.css">

            <!-- 2 -->
            <script src="//cdn.knightlab.com/libs/timeline3/latest/js/timeline.js"></script>

            <div id='timeline-embed' style="width: 100%; height: 600px"></div>
            <script type="text/javascript" src="$self->{issue_key}.json"></script>

            <script type="text/javascript">
                var options = $options;
                window.timeline = new TL.Timeline('timeline-embed', timeline_json, options);
            </script>
            <script type="text/javascript" src="color.js"></script>
        </body>
        </html>
    HTML
    open my $fh, ">", "./$self->{issue_key}/$self->{issue_key}.html"
        or croak(
        "Cannot open file $self->{issue_key}\/$self->{issue_key}.html: $!");
    print $fh $html or croak "Cannot print to file, $fh: $!";
    $self->write_subtask_html()
        if defined $self->{timeline_href}->{subtasks};
    return $self;
}

### Write the html for a subtask's TimelineJS
### Convert to use qq{}
sub write_subtask_html {
    my $self = shift;
    foreach ( @{ $self->{timeline_href}->{subtasks} } ) {
        (   my $options = qq[
            {
                initial_zoom: 1,
                timenav_height_percentage: 35
            }
            ]
        ) =~ s/ {4,8,12}//mg;
        ( my $html = <<"    HTML") =~ s/^ {8}//gm;
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        </head>
        <title>$_->{issue_key}: Timeline<\/title>
        <head></head>
        <body>
            <!-- 1 -->
            <link title="timeline-styles" rel="stylesheet" href="//cdn.knightlab.com/libs/timeline3/latest/css/timeline.css">

            <!-- 2 -->
            <script src="//cdn.knightlab.com/libs/timeline3/latest/js/timeline.js"></script>

            <div id='timeline-embed' style="width: 100%; height: 600px"></div>
            <script type="text/javascript" src="$_->{issue_key}.json"></script>

            <script type="text/javascript">
                var options = $options;
                window.timeline = new TL.Timeline('timeline-embed', timeline_json, options);
            </script>
            <script type="text/javascript" src="color.js"></script>
        </body>
        </html>
    HTML
        open my $fh, ">", "./$_->{parent}/$_->{issue_key}.html"
            or croak("Cannot open file $_->{parent}\/$_->{issue_key}: $!\n");
        print $fh $html or croak "Cannot print to file, $fh: $!";

    }
    return $self;
}

1;

