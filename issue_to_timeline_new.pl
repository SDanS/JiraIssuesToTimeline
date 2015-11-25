#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use parent qw( JiraUtils::Issues::ToTimeLine );
use Data::Dumper;

my $start_date;
my $end_date;
my $username;
my $password;
my $issue_key;
my @start_date;
my @end_date;

GetOptions(
    "start_date=s" => \$start_date,
    "end_date=s"   => \$end_date,
    "username=s"   => \$username,
    "password=s"   => \$password,
    "issue_key=s"  => \$issue_key,
);

__PACKAGE__->run() unless caller;

sub run {
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    my $issue = JiraUtils::Issues::ToTimeline->new( $username, $password );
    $issue->{issue_key} = $issue_key;
### expand argument added for reusability.
    $issue->issue_request( 'get', 'changelog' );
    #print Dumper $issue->{jiraIssue};
    $issue->buckets(
        'summary', 'description', 'priority', 'issuetype',
        'status',  'Sprint',      'assignee', 'comments',
        'Story Points'
    );
    #print Dumper $issue->{buckets}->{status};
    #use Data::Dumper;
    print Dumper $issue->{timeline_href};
    $issue->span_tile_events();
    $issue->scope_events();
    $issue->comment_events();
    #print Dumper $issue;
    $issue->issue_dir();
    $issue->write_json();
    $issue->write_html();
}
