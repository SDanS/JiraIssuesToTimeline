package JiraUtils::Issues::Sprint;

use strict;
use warnings;

no warnings 'uninitialized';

use URI::Escape;
use REST::Client;

use JSON;

use parent qw( JiraUtils::Issues );

#use JiraUtils::Issues;

sub new {
    my $class = shift;
    my ( $username, $password ) = @_;
    my $self = $class->SUPER::new( $username, $password );
    return $self;
}

sub issues_in_sprint {
    my $self = shift;
    $self->{sprint_info}->{name} = shift;
    my $expand     = shift;
    my $req_expand = '&expand=' . $expand if $expand;
    my $req_fields = '&fields=key';
    ### JQL query for issues belonging to a sprint.
    ### Sprint = "SWSM" AND issuetype != "5"
    ###  https://jira.cpanel.net/rest/api/2/search?jql=sprint%20%3D%20fatality%20and%20issuetype%20!%3D%205&fields=key
    my $sprint_query
        = 'sprint = '
        . "\"$self->{sprint_info}->{name}\""
        . ' AND issuetype != 5';
    my $uri_query_string = 'jql=' . uri_escape($sprint_query);
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

sub get_issues {
    my $self = shift;
    my ( $start_date, $start_datetime, $end_date, $end_datetime ) = @_;
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}
            = JiraUtils::Issues::Sprint->new( $self->{username},
            $self->{password} );
        $self->{issue_objs}->{$_}->{issue_key} = $_;
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
        $self->{issue_objs}->{$_}
            ->JiraUtils::Issues::ToTimeline::span_tile_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        $self->{issue_objs}->{$_}
            ->JiraUtils::Issues::ToTimeline::scope_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        $self->{issue_objs}->{$_}
            ->JiraUtils::Issues::ToTimeline::comment_events( $start_date,
            $start_datetime, $end_date, $end_datetime );
        delete $self->{issue_objs}->{$_}->{buckets};
    }
    return $self;
}

sub write_issues {
    my $self = shift;
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}
            ->JiraUtils::Issues::ToTimeline::write_json();
        $self->{issue_objs}->{$_}
            ->JiraUtils::Issues::ToTimeline::write_html();
    }
    return $self;
}

sub build_overview_obj {
    my $self = shift;
    my ($terminal_start_date, $terminal_start_datetime,
        $terminal_end_date,   $terminal_end_datetime
    ) = @_;
    my $story_ref;
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $self->{issue_objs}->{$_}->{story_ov_obj}   = [];
        $self->{issue_objs}->{$_}->{subtask_ov_obj} = [];
    }
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        $story_ref = $self->{issue_objs}->{$_};
        my $issue_key = $story_ref->{issue_key};
        foreach ( @{ $story_ref->{timeline_href}->{events} } ) {
            if ( $_->{group} eq 'status' ) {
                my @row_array;
                my $start_date;
                my $end_date;
                my ($status) = $_->{text}->{text} =~ /.* to (.+)/;
                if ( exists $_->{start_date} ) {
                    $start_date
                        = "Date($_->{start_date}->{year}, "
                        . ( $_->{start_date}->{month} - 1 )
                        . ",$_->{start_date}->{day}, $_->{start_date}->{hour}, $_->{start_date}->{minute})";
                }
                else {
                    $start_date
                        = "Date($terminal_start_date->{year}, "
                        . ( $terminal_start_date->{month} - 1 )
                        . ", $terminal_start_date->{day}, $terminal_start_date->{hour}, $terminal_start_date->{minute})";
                }
                if ( exists $_->{end_date} ) {
                    $end_date
                        = "Date($_->{end_date}->{year}, "
                        . ( $_->{end_date}->{month} - 1 )
                        . ", $_->{end_date}->{day}, $_->{end_date}->{hour}, $_->{end_date}->{minute})";
                }
                else {
                    $end_date
                        = "Date($terminal_end_date->{year}, "
                        . ( $terminal_end_date->{month} - 1 )
                        . ", $terminal_end_date->{day}, $terminal_end_date->{hour}, $terminal_end_date->{minute})";
                }
                push @row_array,
                    [
                    $issue_key . ": status",
                    $status, $start_date, $end_date
                    ];
                push @{ $story_ref->{story_ov_obj} }, @row_array;
            }
            elsif ( $_->{group} eq 'assignee' ) {
                my @row_array;
                my $start_date;
                my $end_date;
                my ($assignee) = $_->{text}->{text} =~ /.* to (.+)/;
                if ( exists $_->{start_date} ) {
                    $start_date
                        = "Date($_->{start_date}->{year}, "
                        . ( $_->{start_date}->{month} - 1 )
                        . ", $_->{start_date}->{day}, $_->{start_date}->{hour}, $_->{start_date}->{minute})";
                }
                else {
                    $start_date
                        = "Date($terminal_start_date->{year}, "
                        . ( $terminal_start_date->{month} - 1 )
                        . ", $terminal_start_date->{day}, $terminal_start_date->{hour}, $terminal_start_date->{minute})";
                }
                if ( exists $_->{end_date} ) {
                    $end_date
                        = "Date($_->{end_date}->{year}, "
                        . ( $_->{end_date}->{month} - 1 )
                        . ", $_->{end_date}->{day}, $_->{end_date}->{hour}, $_->{end_date}->{minute})";
                }
                else {
                    $end_date
                        = "Date($terminal_end_date->{year}, "
                        . ( $terminal_end_date->{month} - 1 )
                        . ", $terminal_end_date->{day}, $terminal_end_date->{hour}, $terminal_end_date->{minute})";
                }
                push @row_array,
                    [
                    $issue_key . ": assignee",
                    $assignee, $start_date, $end_date
                    ];
                push @{ $story_ref->{story_ov_obj} }, @row_array;
            }
        }
        foreach ( @{ $story_ref->{timeline_href}->{subtasks} } ) {
            my $subtask_ref = $_;
            my $issue_key   = $_->{issue_key};
            my $parent      = $_->{parent};
            $story_ref->{subtask_count}++;
            $story_ref->{subtasks}->{$issue_key} = {};
            foreach ( @{ $_->{events} } ) {
                my $start_date;
                my $end_date;
                if ( $_->{group} eq 'status' ) {
                    my @row_array;
                    $story_ref->{subtask_statuses}++;
                    my ($status) = $_->{text}->{text} =~ /.* to (.+)/;
                    if ( exists $_->{start_date} ) {
                        $start_date
                            = "Date($_->{start_date}->{year}, "
                            . ( $_->{start_date}->{month} - 1 )
                            . ", $_->{start_date}->{day}, $_->{start_date}->{hour}, $_->{start_date}->{minute})";
                    }
                    else {
                        $start_date
                            = "Date($terminal_start_date->{year}, "
                            . ( $terminal_start_date->{month} - 1 )
                            . ", $terminal_start_date->{day}, $terminal_start_date->{hour}, $terminal_start_date->{minute})";
                    }
                    if ( exists $_->{end_date} ) {
                        $end_date
                            = "Date($_->{end_date}->{year}, "
                            . ( $_->{end_date}->{month} - 1 )
                            . ", $_->{end_date}->{day}, $_->{end_date}->{hour}, $_->{end_date}->{minute})";
                    }
                    else {
                        $end_date
                            = "Date($terminal_end_date->{year}, "
                            . ( $terminal_end_date->{month} - 1 )
                            . ", $terminal_end_date->{day}, $terminal_end_date->{hour}, $terminal_end_date->{minute})";

                    }
                    push @row_array,
                        [
                        $issue_key . ": status",
                        $status, $start_date, $end_date
                        ];
                    push @{ $story_ref->{subtask_ov_obj} }, @row_array;
                }
                elsif ( $_->{group} eq 'assignee' ) {
                    my @row_array;
                    $story_ref->{subtask_assignee_delta}++;
                    my ($assignee) = $_->{text}->{text} =~ /.* to (.+)/;
                    if ( exists $_->{start_date} ) {
                        $start_date
                            = "Date($_->{start_date}->{year}, "
                            . ( $_->{start_date}->{month} - 1 )
                            . ", $_->{start_date}->{day}, $_->{start_date}->{hour}, $_->{start_date}->{minute})";
                    }
                    else {
                        $start_date
                            = "Date($terminal_start_date->{year}, "
                            . ( $terminal_start_date->{month} - 1 )
                            . ", $terminal_start_date->{day}, $terminal_start_date->{hour}, $terminal_start_date->{minute})";
                    }
                    if ( exists $_->{end_date} ) {
                        $end_date
                            = "Date($_->{end_date}->{year}, "
                            . ( $_->{end_date}->{month} - 1 )
                            . ", $_->{end_date}->{day}, $_->{end_date}->{hour}, $_->{end_date}->{minute})";
                    }
                    else {
                        $end_date
                            = "Date($terminal_end_date->{year}, "
                            . ( $terminal_end_date->{month} - 1 )
                            . ", $terminal_end_date->{day}, $terminal_end_date->{hour}, $terminal_end_date->{minute})";
                    }
                    push @row_array,
                        [
                        $issue_key . ": assignee",
                        $assignee, $start_date, $end_date
                        ];
                    push @{ $story_ref->{subtask_ov_obj} }, @row_array;
                }
            }
        }
        my @header_row = (
            [
                # [   'Issue',
                #     'Field Type',
                #     'Field Value',
                'Row Label',
                'Bar Label',

                #{ type => 'string', role  => 'tooltip' },
                { type => 'date', label => 'Start' },
                { type => 'date', label => 'End' }
            ]
        );
        unshift @{ $story_ref->{story_ov_obj} }, @header_row;
    }
    return $self;
}

sub write_overview_obj_json {
    my $self = shift;
    foreach ( keys %{ $self->{issue_objs} } ) {
        open my $story_fh, ">",
            "./$self->{issue_objs}->{$_}->{issue_key}.json";
        open my $subtask_fh, ">",
            "./$self->{issue_objs}->{$_}->{issue_key}" . 'subtasks.json';
        push @{ $self->{issue_objs}->{$_}->{story_ov_obj} },
            @{ $self->{issue_objs}->{$_}->{subtask_ov_obj} };
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

sub dir_setup {
    my $self = shift;
    $self->{sprint_info}->{sprint_dir} = "./$self->{sprint_info}->{name}";
    mkdir "./$self->{sprint_info}->{sprint_dir}";
    chdir $self->{sprint_info}->{sprint_dir};
    foreach ( @{ $self->{sprint_info}->{story_keys} } ) {
        mkdir "./$_";
    }
    return $self;
}

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

sub ov_index_html {
    my $self = shift;
    my $story_ref;
    (   my $html_tag_open = qq{
        <html>
        <title> Sprint: $self->{sprint_name}</title>
        <head>
            <meta charset="UTF-8" />
            <link rel="stylesheet" type="text/css" href="menu.css"/>
        </head>
        <body>
        <h2>Sprint: $self->{sprint_name}</h2>
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
        $self->{index_html}
            .= '<li><a href="'
            . "./$story_ref->{issue_key}.html" . '">'
            . $story_ref->{issue_key} . ": "
            . $story_ref->{summary}
            . '<br><span style="color: red;">'
            . 'Subtasks count: ['
            . $story_ref->{subtask_count}
            . '] Status changes: ['
            . $story_ref->{subtask_statuses}
            . '] Assignee changes: ['
            . $story_ref->{subtask_assignee_delta}
            . ']</span></a></li>' . "\n";
    }
    # (   my $body_div = qq{
    #     <div class="body_offset">
    #     <br><br>
    #     <h2><a>$self->{sprint_name}</a></h2>
    #     </div>
    #     }
    # ) =~ s/ {4,8}//mg;
    $self->{index_html} .= $ul_div_close . $html_tag_close;
}

sub write_index_html {
    my $self = shift;
    open my $fh, '>', './index.html';
    print $fh $self->{index_html};

}

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
              <div id="chart-div" style="width: 1000px; height: 2000px;"></div>
            </div>
            </body>
            </html>
            }
        ) =~ s/ {12}//mg;
    }
    return $self;
}

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
    open my $fh, '>', './menu.css';
    print $fh $css;
    return $self;

}

sub ov_write_html {
    my $self = shift;
    foreach ( keys $self->{issue_objs} ) {
        my $story_ref = $self->{issue_objs}->{$_};
        open my $fh, '>', "./$story_ref->{issue_key}.html";
        print $fh $story_ref->{main_html};
    }
    return $self;
}

1;
