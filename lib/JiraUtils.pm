package JiraUtils;

use strict;
use warnings;

no warnings 'uninitialized';


use REST::Client;
use MIME::Base64 qw(encode_base64);
use DateTime::Format::ISO8601;

sub new {
    my $self  = {};
    my $class = shift;
    bless( $self, $class );
    return $self;
}

### Create a universal REST::Client instance for entire process.
sub client {
    my $self = shift;
    my ($username, $password) = @_;
    $self->{username}     = $username;
    $self->{password}     = $password;
    $self->{auth_headers} = {
        Accept        => 'application/json',
        Authorization => 'Basic '
            . encode_base64( $username . ':' . $password ),
        'Content-Type' => 'application/json',
    };
    $self->{client} = REST::Client->new();
    $self->{client}->setHost("https://jira.cpanel.net");
    return $self;   
}

### For converting Jira's time format to something more useful.
sub dt_iso_8601 {
    my $time          = shift;
    my @stripped_time = split( '\.', $time );
    my $iso8601       = DateTime::Format::ISO8601->new;
    my $datetime      = $iso8601->parse_datetime( $stripped_time[0] );
    return $datetime;
}

1;
