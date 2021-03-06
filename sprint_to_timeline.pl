#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use JiraUtils::Issues::Sprint;
use Carp;

use DateTime;

#use Data::Dumper;

no warnings 'uninitialized';

my @start_date;
my @end_date;
my $username;
my $password;
my $sprint_name;
my $project;
my @issues;
my $dir_name;

GetOptions(
    "start_date=s{5}" => \@start_date,
    "end_date=s{5}"   => \@end_date,
    "username=s"      => \$username,
    "password=s"      => \$password,
    "sprint_name=s"   => \$sprint_name,
    "issues=s{1,}"    => \@issues,
    "dir_name=s"      => \$dir_name,
);

__PACKAGE__->run() unless caller;

sub run {
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    croak '--dir_name and --sprint_name are mutually exclusive options'
        if ( $sprint_name && $dir_name );
    croak 'Must provide both a username or password'
        if ( ( !$username ) || ( !$password ) );
    croak 'Must provide --issues or a query when using --dir_name'
        if ( ($dir_name) && ( !@issues ) );
    my $sprint = JiraUtils::Issues::Sprint->new();
    $sprint->client( $username, $password );
    $sprint->{end_datetime} = DateTime->new(
        year   => $end_date[0],
        month  => $end_date[1],
        day    => $end_date[2],
        hour   => $end_date[3],
        minute => $end_date[4]
    ) if $end_date[0];
    $sprint->{end_date} = {
        year   => $sprint->{end_datetime}->year,
        month  => $sprint->{end_datetime}->month,
        day    => $sprint->{end_datetime}->day,
        hour   => $sprint->{end_datetime}->hour,
        minute => $sprint->{end_datetime}->minute
        }
        if @end_date;
    $sprint->{start_datetime} = DateTime->new(
        year   => $start_date[0],
        month  => $start_date[1],
        day    => $start_date[2],
        hour   => $start_date[3],
        minute => $start_date[4]
    ) if $start_date[0];
    $sprint->{start_date} = {
        year   => $sprint->{start_datetime}->year,
        month  => $sprint->{start_datetime}->month,
        day    => $sprint->{start_datetime}->day,
        hour   => $sprint->{start_datetime}->hour,
        minute => $sprint->{start_datetime}->minute
        }
        if @start_date;
    $sprint->{sprint_name} = $sprint_name;
    $sprint->{dir_name}    = $dir_name;

    $sprint->issues_in_query( $sprint_name, \@issues );
    $sprint->dir_setup($dir_name);
    $sprint->get_issues(
        $sprint->{start_date}, $sprint->{start_datetime},
        $sprint->{end_date},   $sprint->{end_datetime}
    );
    $sprint->build_overview_obj(
        $sprint->{start_date}, $sprint->{start_datetime},
        $sprint->{end_date},   $sprint->{end_datetime}
    );
    $sprint->write_issues();
    $sprint->write_overview_obj_json();
    $sprint->ov_gather_links_for_html();
    $sprint->ov_nav_menu_html();
    $sprint->ov_static_html();
    $sprint->ov_menu_css();
    $sprint->ov_write_html();
    $sprint->ov_index_html();
    $sprint->write_index_html();
}
