package JiraUtils::Issues::ToTimeline;

use strict;
use warnings;

no warnings 'uninitialized';

use parent qw(JiraUtils::Issues);

use JSON;
use DateTime qw( compare );

#use Data::Dumper;

sub new {
    my $class = shift;
    my ( $username, $password ) = @_;
    my $self = $class->SUPER::new( $username, $password );
    return $self;
}

sub subtask_builder {
    my $self   = shift;
    my $parent = shift;
    my ( $start_date, $start_datetime, $end_date, $end_datetime ) = @_;
    foreach ( @{ $self->{jiraIssue}->{fields}->{subtasks} } ) {
        my $subtask = JiraUtils::Issues::ToTimeline->new( $self->{username},
            $self->{password} );
        $subtask->{issue_key} = $_->{key};
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

        #$subtask->issue_dir();
        #$subtask->write_json();
        #$subtask->write_html();
    }
    return $self;
}

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
            foreach ( @{ $bucket_instance->{items} } ) {
                if ( $_->{field} eq $current_bucket ) {
                    my $to_string   = $_->{toString}   // 'unassigned';
                    my $from_string = $_->{fromString} // 'unassigned';

                    #$text->{headline} = ucfirst( $_->{field} ) . " changed.";
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
                if ( defined $cmp && $cmp == 1 ) {
                    push @{ $self->{timeline_href}->{events} }, $event;
                }
            }
        }
    }
    return $self;
}

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

sub issue_dir {
    my $self = shift;
    unless ( mkdir "./$self->{issue_key}" ) {
        die "Unable to create $self->{issue_key}: $!";
    }
    return $self;
}

sub write_json {
    my $self = shift;
    open my $fh, ">", "./$self->{issue_key}/$self->{issue_key}.json"
        or die("Cannot open filehandle $self->{issue_key}: $!\n");
    print $fh "var timeline_json = "
        . to_json( $self->{'timeline_href'},
        { pretty => 1, allow_blessed => 1 } )
        or die("Cannot print to $self->{key}: $!");
    $self->JiraUtils::Issues::ToTimeline::write_subtask_json()
        if defined $self->{timeline_href}->{subtasks};

    return $self;
}

sub write_subtask_json {
    my $self = shift;
    foreach ( @{ $self->{timeline_href}->{subtasks} } ) {
        open my $fh, ">", "./$_->{parent}/$_->{issue_key}.json"
            or die("Cannot open filehandle $_->{issue_key}: $!\n");
        print $fh "var timeline_json = "
            . to_json( $_, { pretty => 1, allow_blessed => 1 } )
            or
            die("Cannot print to $_->{parent}\/$_->{issue_key}.json: $!\n");
    }
    return $self;
}

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
        <meta charset=\"UTF-8\">
        </head>
        <title>$self->{issue_key}: Timeline<\/title>
        <head><\/head>
        <body>
            <!-- 1 -->
            <link title=\"timeline-styles\" rel=\"stylesheet\" href=\"\/\/cdn.knightlab.com\/libs\/timeline3\/latest\/css\/timeline.css\">

            <!-- 2 -->
            <script src=\"\/\/cdn.knightlab.com\/libs\/timeline3\/latest\/js\/timeline.js\"><\/script>

            <div id=\'timeline-embed\' style=\"width: 100%; height: 600px\"><\/div>
            <script type=\"text\/javascript\" src=\"$self->{issue_key}.json\"><\/script>

            <script type=\"text\/javascript\">
                var options = $options;
                window.timeline = new TL.Timeline(\'timeline-embed\', timeline_json, options);
            <\/script>
            <script type="text/javascript">
                for (index = 0; index < document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline').length; index++) {  
                  var colors = {
                    'In Progress': 'darkcyan',
                    'In Review': 'dodgerblue',
                    'To Do': 'gray',
                    'In Test': 'darkblue',
                    'Merge Pending': 'slateblue',
                    'Done': 'indigo'
                  };
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Progress/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor = "darkcyan";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Review/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "dodgerblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/To Do/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "gray";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Test/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "darkblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Merge Pending/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "slateblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Done/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "indigo";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Assignee.*/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "seagreen";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Assignee: unassigned/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "indianred";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Comment/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "olivedrab";
                  } 
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Summary/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  }             
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Description/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  } 
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Story Points/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Priority/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "plum";
                  }   
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Issuetype/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "plum";
                  }  
                }
                var arr = document.querySelectorAll('div.tl-timegroup');
                for (index = 0; index < arr.length; index++) {
                  if ( arr[index].className.match(/tl-timegroup\$/) ) {
                    arr[index].style.backgroundColor = "lightgray";
                  }
                }
                var arr2 = document.querySelectorAll('div.tl-timegroup-message');
                for (index = 0; index < arr2.length; index++) {
                    arr2[index].style.color = "gray";
                }
            </script>
        <\/body>
        <\/html>
    HTML
    open my $fh, ">", "./$self->{issue_key}/$self->{issue_key}.html"
        or die(
        "Cannot open file $self->{issue_key}\/$self->{issue_key}.html: $!");
    print $fh $html;
    $self->JiraUtils::Issues::ToTimeline::write_subtask_html()
        if defined $self->{timeline_href}->{subtasks};
    return $self;
}

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
        <meta charset=\"UTF-8\">
        </head>
        <title>$_->{issue_key}: Timeline<\/title>
        <head><\/head>
        <body>
            <!-- 1 -->
            <link title=\"timeline-styles\" rel=\"stylesheet\" href=\"\/\/cdn.knightlab.com\/libs\/timeline3\/latest\/css\/timeline.css\">

            <!-- 2 -->
            <script src=\"\/\/cdn.knightlab.com\/libs\/timeline3\/latest\/js\/timeline.js\"><\/script>

            <div id=\'timeline-embed\' style=\"width: 100%; height: 600px\"><\/div>
            <script type=\"text\/javascript\" src=\"$_->{issue_key}.json\"><\/script>

            <script type=\"text\/javascript\">
                var options = $options;
                window.timeline = new TL.Timeline(\'timeline-embed\', timeline_json, options);
            <\/script>
            <script type="text/javascript">
                for (index = 0; index < document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline').length; index++) {  
                  var colors = {
                    'In Progress': 'darkcyan',
                    'In Review': 'dodgerblue',
                    'To Do': 'gray',
                    'In Test': 'darkblue',
                    'Merge Pending': 'slateblue',
                    'Done': 'indigo'
                  };
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Progress/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor = "darkcyan";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Review/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "dodgerblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/To Do/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "gray";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/In Test/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "darkblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Merge Pending/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "slateblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Done/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "indigo";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Assignee.*/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "seagreen";
                  }  
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Assignee: unassigned/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "indianred";
                  }  
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Comment/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "olivedrab";
                  }                                
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Summary/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  }             
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Description/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  } 
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Story Points/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "palevioletred";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Priority/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "plum";
                  }   
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Issuetype/mg)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "plum";
                  }
                }
                var arr = document.querySelectorAll('div.tl-timegroup');
                for (index = 0; index < arr.length; index++) {
                  if ( arr[index].className.match(/tl-timegroup\$/) ) {
                    arr[index].style.backgroundColor = "lightgray";
                  }
                }
                var arr2 = document.querySelectorAll('div.tl-timegroup-message');
                for (index = 0; index < arr2.length; index++) {
                    arr2[index].style.color = "gray";
                }
            </script>
        <\/body>
        <\/html>
    HTML
        open my $fh, ">", "./$_->{parent}/$_->{issue_key}.html"
            or die("Cannot open file $_->{parent}\/$_->{issue_key}: $!\n");
        print $fh $html;

    }
    return $self;
}

1;
