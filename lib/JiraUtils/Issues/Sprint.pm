package JiraUtils::Issues::Sprint;

use strict;
use warnings;

no warnings 'uninitialized';

use URI::Escape;
use REST::Client;
use Carp;
use DateTime;

use JSON;

use parent qw( JiraUtils::Issues );

sub new {
    my $class = shift;
    my ( $username, $password ) = @_;
    my $self = $class->SUPER::new();
    return $self;
}

### Find out what issues (not subtasks) belong to a sprint.
sub issues_in_query {
    my $self = shift;
    $self->{sprint_info}->{name}   = shift;
    $self->{sprint_info}->{issues} = shift;
    my $expand     = shift;
    my $req_expand = '&expand=' . $expand if $expand;
    my $req_fields = '&fields=key';
    my $sprint_query
        = 'sprint = '
        . "\"$self->{sprint_info}->{name}\""
        . ' AND issuetype != 5';
    my $issue_string;
    foreach ( 0 .. $#{ $self->{sprint_info}->{issues} } ) {
        $issue_string .= $self->{sprint_info}->{issues}->[$_] . ','
            unless $_ == $#{ $self->{sprint_info}->{issues} };
        $issue_string .= $self->{sprint_info}->{issues}->[$_]
            if $_ == $#{ $self->{sprint_info}->{issues} };
    }
    my $issue_query      = 'issue in (' . $issue_string . ')';
    my $uri_query_string = 'jql=' . uri_escape($sprint_query)
        if $self->{sprint_info}->{name};
    $uri_query_string = 'jql=' . uri_escape($issue_query)
        if ( !( $self->{sprint_info}->{name} ) && ($issue_string) );

    $self->{client}->GET(
        'rest/api/2/search?' . $uri_query_string . $req_expand . $req_fields,
        $self->{auth_headers}
    );
    $self->{sprint} = from_json( $self->{client}->responseContent() );

    foreach ( @{ $self->{sprint}->{issues} } ) {
        push @{ $self->{sprint_info}->{story_keys} }, $_->{key};
    }
    return $self;
}

### Get the issues and their subtasks.
sub get_issues {
    my $self = shift;
    my ( $start_date, $start_datetime, $end_date, $end_datetime ) = @_;
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}
            = JiraUtils::Issues::Sprint->new( $self->{username},
            $self->{password} );
        $self->{issue_objs}->{$_}->{issue_key}    = $_;
        $self->{issue_objs}->{$_}->{client}       = $self->{client};
        $self->{issue_objs}->{$_}->{auth_headers} = $self->{auth_headers};
        $self->{issue_objs}->{$_}->issue_request( 'get', 'changelog' );
        my $buckets = [
            'summary', 'description', 'priority', 'issuetype',
            'status',  'Sprint',      'assignee', 'comments',
            'Story Points'
        ];
        $self->{issue_objs}->{$_}->buckets(
            $buckets,  $start_date, $start_datetime,
            $end_date, $end_datetime
        );
        $self->{issue_objs}->{$_}->span_tile_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        $self->{issue_objs}->{$_}->scope_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        $self->{issue_objs}->{$_}->comment_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        delete $self->{issue_objs}->{$_}->{buckets};
    }
    return $self;
}

### Write out those issues and their subtasks if they exist.
sub write_issues {
    my $self = shift;
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}->write_json();
        $self->{issue_objs}->{$_}->write_html();
    }
    return $self;
}

### Build data structure for Google Timeline story overview.
sub build_overview_obj {
    my $self = shift;
    my ($terminal_start_date, $terminal_start_datetime,
        $terminal_end_date,   $terminal_end_datetime
    ) = @_;
    my $story_ref;

    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}->{story_ov_obj} = [];
    }
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $story_ref = $self->{issue_objs}->{$_};
        my $issue_key = $story_ref->{issue_key};
        foreach ( @{ $story_ref->{timeline_href}->{events} } ) {
            if ( $_->{group} eq 'status' || $_->{group} eq 'assignee' ) {
                my $event_type = $_->{group};
                my @row_array;
                my ($status) = $_->{text}->{text} =~ /.* to (.+)/;
                my ( $start_date, $end_date )
                    = date_termination( $_, $terminal_start_date,
                    $terminal_end_date );
                push @row_array,
                    [
                    $issue_key . ': ' . $event_type,
                    $status, $start_date, $end_date
                    ];
                push @{ $story_ref->{story_ov_obj} }, @row_array;
            }
        }
        foreach ( @{ $story_ref->{timeline_href}->{subtasks} } ) {
            my $subtask_ref = $_;
            my $issue_key   = $_->{issue_key};
            my $parent      = $_->{parent};
            my ( $event_type, $status, $start_date, $end_date );
            my @placeholder_row;
            $story_ref->{subtask_count}++;
            $story_ref->{subtasks}->{$issue_key} = {};
            foreach ( @{ $_->{events} } ) {
                my @row_array;
                my $subtask_event = $_;
                if ( $_->{group} eq 'status' || $_->{group} eq 'assignee' ) {
                    $subtask_ref->{ $_->{group} . '_count' }++;
                    $story_ref->{ $_->{group} . '_count' }++;
                    $event_type = $_->{group};
                    ($status) = $_->{text}->{text} =~ /.* to (.+)/;
                    ( $start_date, $end_date )
                        = date_termination( $_, $terminal_start_date,
                        $terminal_end_date );

                    push @row_array,
                        [
                        $issue_key . ': ' . $event_type,
                        $status, $start_date, $end_date
                        ];
                    push @{ $story_ref->{story_ov_obj} }, @row_array;
                }
            }
            unless ( $subtask_ref->{status_count} ) {
                ### Switch to &date_determination and pass in $subtask_event.
                my ( $start_date, $end_date )
                    = date_termination( {}, $terminal_start_date,
                    $terminal_end_date );

                push @placeholder_row,
                    [
                    $issue_key . ': status', 'No Status Changes',
                    $start_date,             $end_date
                    ];
                push @{ $story_ref->{story_ov_obj} }, @placeholder_row;
            }
            unless ( $subtask_ref->{assignee_count} ) {
                my ( $start_date, $end_date )
                    = date_termination( {}, $terminal_start_date,
                    $terminal_end_date );

                push @placeholder_row,
                    [
                    $issue_key . ': assignee', 'No Assignee Changes',
                    $start_date,               $end_date
                    ];

                push @{ $story_ref->{story_ov_obj} }, @placeholder_row;
            }

        }
        my @header_row = (
            [   'Row Label',
                'Bar Label',
                { type => 'date', label => 'Start' },
                { type => 'date', label => 'End' }
            ]
        );

        unshift @{ $story_ref->{story_ov_obj} }, @header_row;
    }
    return $self;
}

### Handle date cutoffs.
sub date_termination {
    my ( $event, $terminal_start_date, $terminal_end_date ) = @_;
    my ( $start_date, $end_date );
    if ( defined $event->{start_date} ) {
        $start_date
            = "Date($event->{start_date}->{year}, "
            . ( $event->{start_date}->{month} - 1 )
            . " ,$event->{start_date}->{day}, $event->{start_date}->{hour}, $event->{start_date}->{minute})";
    }
    else {
        $start_date
            = "Date($terminal_start_date->{year}, "
            . ( $terminal_start_date->{month} - 1 )
            . ", $terminal_start_date->{day},  $terminal_start_date->{hour}, $terminal_start_date->{minute})";
    }
    if ( defined $event->{end_date} ) {
        $end_date
            = "Date($event->{end_date}->{year}, "
            . ( $event->{end_date}->{month} - 1 )
            . ", $event->{end_date}->{day}, $event->{end_date}->{hour}, $event->{end_date}->{minute})";
    }
    else {
        $end_date
            = "Date($terminal_end_date->{year}, "
            . ( $terminal_end_date->{month} - 1 )
            . ", $terminal_end_date->{day}, $terminal_end_date->{hour}, $terminal_end_date->{minute})";
    }
    return ( $start_date, $end_date );

}

### Write javascript for overview.
sub write_overview_obj_json {
    my $self = shift;
    foreach ( keys %{ $self->{issue_objs} } ) {
        open my $story_fh, ">",
            "./$self->{issue_objs}->{$_}->{issue_key}.json";
        open my $subtask_fh, ">",
            "./$self->{issue_objs}->{$_}->{issue_key}" . 'subtasks.json';
        my $story_ov_json
            = to_json( $self->{issue_objs}->{$_}->{story_ov_obj},
            { pretty => 1 } );
        (   my $story_script = qq{
        google.load(\'visualization\', \'1\', {packages\: [\'timeline\']});
        google.setOnLoadCallback(drawChart);

        function drawChart() {
            var data = google.visualization.arrayToDataTable($story_ov_json);
            var options = {
                avoidOverlappingGridLines: false,
                allowHtml: true,
            };
            var view = new google.visualization.DataView(data);
            //view.setColumns([]);
            var Container = document.getElementById('chart-div');
            var chart = new google.visualization.Timeline(Container);


            chart.draw(view, options);
        }}
        ) =~ s/^ {8}//mg;
        print $story_fh $story_script;
    }
    return $self;
}

### Setup sprint directory.
sub dir_setup {
    my $self     = shift;
    my $dir_name = shift;
    $self->{sprint_info}->{sprint_dir} = "./$self->{sprint_info}->{name}"
        unless $dir_name;
    $self->{sprint_info}->{sprint_dir} = $dir_name if $dir_name;
    mkdir "./$self->{sprint_info}->{sprint_dir}";
    chdir $self->{sprint_info}->{sprint_dir};
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        mkdir "./$_";
    }
    return $self;
}

### Build html for sidenav on overview.
sub ov_gather_links_for_html {
    my $self = shift;
    my $story_ref;
    my $subtask_ref;
    foreach ( keys $self->{issue_objs} ) {
        $story_ref = $self->{issue_objs}->{$_};
        $story_ref->{link}
            = "./$story_ref->{issue_key}/$story_ref->{issue_key}.html";
        $story_ref->{link_text} = "$story_ref->{issue_key}";
        if ( defined $story_ref->{subtasks} ) {
            foreach ( keys $story_ref->{subtasks} ) {
                $subtask_ref = $story_ref->{subtasks}->{$_};
                $subtask_ref->{link} = "./$story_ref->{issue_key}/$_.html";
                $subtask_ref->{link_text} = "$_";
            }
        }
    }
    return $self;
}

### Build html for the rest of the sidenav menu.
sub ov_nav_menu_html {
    my $self = shift;
    my $story_ref;
    my $subtask_ref;
    my $div_ul_open  = '<div class="menu_simple">' . "\n" . '<ul>' . "\n";
    my $ul_div_close = '</ul>' . "\n" . '</div>' . "\n";
    foreach ( keys $self->{issue_objs} ) {
        $story_ref = $self->{issue_objs}->{$_};
        $story_ref->{nav_menu_html}
            = $div_ul_open
            . '<li><a href="'
            . $story_ref->{link} . '">'
            . $story_ref->{issue_key}
            . '</a></li>' . "\n";
        if ( defined $story_ref->{subtasks} ) {
            foreach ( keys $story_ref->{subtasks} ) {
                $subtask_ref = $story_ref->{subtasks}->{$_};
                $story_ref->{nav_menu_html}
                    .= '<li><a href="'
                    . $subtask_ref->{link} . '">'
                    . $subtask_ref->{link_text}
                    . '</a></li>' . "\n";
            }
        }
        $story_ref->{nav_menu_html} .= $ul_div_close;
    }
    return $self;
}

### Build the sprint overview menu/index page.
sub ov_index_html {
    my $self = shift;
    my $story_ref;
    $self->{sprint_name} = $self->{dir_name} if $self->{dir_name};
    (   my $html_tag_open = qq{
        <html>
        <title> Report: $self->{sprint_name}</title>
        <head>
            <meta charset="UTF-8" />
            <link rel="stylesheet" type="text/css" href="menu.css"/>
        </head>
        <body>
        <h2>Report: $self->{sprint_name}</h2>
    }
    ) =~ s/ {4,8}//mg;
    (   my $html_tag_close = qq{
        </body>
        </html>
    }
    ) =~ s/ {4,8}//mg;
    my $div_ul_open  = '<div class="menu_sprint">' . "\n" . '<ul>' . "\n";
    my $ul_div_close = '</ul>' . "\n" . '</div>';
    $self->{index_html} = $html_tag_open . $div_ul_open;

    foreach ( keys $self->{issue_objs} ) {
        $story_ref = $self->{issue_objs}->{$_};
        $story_ref->{status_count}, $story_ref->{assignee_count};
        $self->{index_html}
            .= '<li><a href="'
            . "./$story_ref->{issue_key}.html" . '">'
            . $story_ref->{issue_key} . ": "
            . $story_ref->{summary}
            . '<br><span style="color: red;">'
            . 'Subtasks count: ['
            . $story_ref->{subtask_count}
            . '] Status changes: ['
            . $story_ref->{status_count}
            . '] Assignee changes: ['
            . $story_ref->{assignee_count}
            . ']</span></a></li>' . "\n";
    }
    $self->{index_html} .= $ul_div_close . $html_tag_close;
}

### Write the sprint overview page.
sub write_index_html {
    my $self = shift;
    my $fh;
    open $fh, '>', './index.html'
        or croak "Cannot open filehandle, $fh: $!";
    print $fh $self->{index_html}
        or croak "Cannot print to filehandle, $fh: $!";

}

### Build Story/Issue Google Timeline overview page.
sub ov_static_html {
    my $self = shift;
    my $story_ref;
    my $subtask_ref;
    foreach ( keys $self->{issue_objs} ) {
        $story_ref = $self->{issue_objs}->{$_};
        (   $story_ref->{main_html} = qq{
            <html>
            <head>
              <meta charset="UTF-8" />
              <link rel="stylesheet" type="text/css" href="menu.css"/>
            </head>
            <title>$story_ref->{issue_key} - Sprint $self->{sprint_name}</title>
            <body>
            $story_ref->{nav_menu_html}
              <div class="body_offset">
              <h2><a href="https://jira.cpanel.net/browse/$story_ref->{issue_key}">$story_ref->{issue_key}: $story_ref->{summary}</a></h2>
              <script type="text/javascript" src="https://www.google.com/jsapi?autoload={'modules':[{'name':'visualization',
       'version':'1','packages':['timeline']}]}"></script>
              <script type="text/javascript" src="./$story_ref->{issue_key}.json"></script>
              <div id="chart-div" style="width: 100%; height: 100%;"></div>
            </div>
            </body>
            </html>
            }
        ) =~ s/ {12}//mg;
    }
    return $self;
}

### CSS for stuff.
sub ov_menu_css {
    my $self = shift;
    (   my $css = qq[
/* CSSTerm.com Simple CSS menu */

.menu_simple ul {
margin: 0; 
padding: 10px 7px 5px;
width:185px;
left: 10px;
list-style-type: none;
position: fixed;
max-height: 800px;
overflow-x: hidden;
overflow-y: auto;
}

.menu_simple ul li a {
    text-decoration: none;
    color: black; 
    padding: 10.5px 11px;
    background-color: #005555;
    background-color: #FFFFFF;
    display:block;
    border-color: #5FD367;
}
 
.menu_simple ul li a:visited {
    color: purple;
}
 
.menu_simple ul li a:hover, .menu_simple ul li .current {
    color: purple;
    background-color: #5FD367;
}

.body_offset {
    margin-left: 225px;
    margin-top: 0px;
}
 
.menu_sprint ul {
    margin: 0;
    padding: 10px 7px 5px;
    width:1000px;
    left: 10px;
    list-style-type: none;
    position: relative;
    max-height: 800px;
    overflow-x: hidden;
    overflow-y: auto;
}

.menu_sprint ul li a {
    text-decoration: none;
    color: black;
    padding: 10.5px 11px;
    background-color: #005555;
    background-color: #FFFFFF;
    display:block;
    border-color: #5FD367;
}

.menu_sprint ul li a:visited {
    color: purple;
}

.menu_sprint ul li a:hover, .menu_simple ul li .current {
    color: purple;
    background-color: #5FD367;
}
]
    ) =~ s/ {4}//mg;
    my $fh;
    open $fh, '>', './menu.css' or croak "Cannot open filehandle, $fh: $!";
    print $fh $css or croak "Cannot print to filehandle, $fh: $!";
    return $self;

}

### Write issue/story overview page
sub ov_write_html {
    my $self = shift;
    foreach ( keys $self->{issue_objs} ) {
        my $story_ref = $self->{issue_objs}->{$_};
        my $fh;
        open $fh, '>', "./$story_ref->{issue_key}.html"
            or croak "Cannot open filehandle, $fh: $!";
        print $fh $story_ref->{main_html}
            or croak "Cannot print to filehandle, $fh: $!";
    }
    return $self;
}

### Colors for TimelineJS
sub colors_js {
    my $self = shift;
    $self->{color_js_text} = qq|
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
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Ready To Accept/img)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "slateblue";
                  }
                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Ready to Merge/img)) {
                    document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small')[index].style.backgroundColor 
                      = "slateblue";
                  }                  if (document.querySelectorAll('div.tl-timemarker-content-container.tl-timemarker-content-container-small h2.tl-headline')[index].innerHTML.match(/Done/mg)) {
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
                }|;
    return $self;
}

1;
