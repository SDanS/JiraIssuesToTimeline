package JiraUtils::Issues;

use strict;
use warnings;

no warnings 'uninitialized';

use REST::Client;
use JSON;

use JiraUtils::Issues::ToTimeline;

#use Data::Dumper;

use parent qw(JiraUtils);

sub new {
    my $class = shift;
    my ( $username, $password ) = @_;
    my $self = $class->SUPER::new( $username, $password );
    return $self;
}

sub issue_request {
    my $self         = shift;
    my $request_type = shift;
    my $expand       = shift;
    my $req_expand   = '?expand=' . $expand if $expand;
    if ( $request_type eq "get" ) {
        $self->{client}
            ->GET( '/rest/api/2/issue/' . $self->{issue_key} . $req_expand,
            $self->{auth_headers} );
        $self->{jiraIssue} = from_json( $self->{client}->responseContent() );
    }
    return $self;
}

### Get out the useful bits and put them into a reasonably shallow hash.
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
    $self->JiraUtils::Issues::ToTimeline::subtask_builder(
        $self->{issue_key}, $start_date, $start_datetime,
        $end_date,          $end_datetime
    ) if defined $self->{jiraIssue}->{fields}->{subtasks};
    $self->{client};
    $self->{histories};
    $self->{jiraIssue};
    return $self;
}

sub title {
    my $self = shift;
    $self->{timeline_href}->{title}->{text}->{headline}
        = "<a href=\"https://jira.cpanel.net/browse/$self->{issue_key}\">$self->{issue_key}: "
        . $self->{summary} . '</a>';
    $self->{timeline_href}->{issue_key} = $self->{issue_key};
    return $self;
}

sub comments_into_bucket {
    my $self = shift;
    $self->{buckets}->{comments}
        = $self->{jiraIssue}->{fields}->{comment}->{comments};
    return $self;
}

1;

