package Export::Connector::Redmine;

use Data::Dumper;
use strict;
use base qw(Export::Connector);
use fields qw(config url username password dryrun _agent apiKey);

# see http://search.cpan.org/~celogeek/Redmine-API-0.03/lib/Redmine/API.pm
use Redmine::API;

use constant ISSUE_CODE => qr/^((T\d+)|[a-zA-Z]{2,}-\d+)/;

sub new {
    my $class = shift;
    my %opt = @_; 

    my $self = fields::new($class);


=head3
   Set keys
=cut
    while (my($key, $value) = each \%opt ){
        $self->$key($value);
    }

    return $self;
}

sub config {
    my ($self, $config) = @_;
    if (defined($config)) {
        $self->{config} = $config;
    }
    return $self->{config};
}

sub apiKey {
    my ($self, $apiKey ) = @_;
    if (defined($apiKey )) {
        $self->{apiKey} = $apiKey;
    }
    return $self->{apiKey};
}

sub url {
    my ($self, $url) = @_;
    if (defined($url)) {
        $url =~ s!/$!!o;
        $self->{url} = $url;
    }
    return $self->{url};
}

sub username {
    my ($self, $username) = @_;
    if (defined($username)) {
        $self->{username} = $username;
    }
    return $self->{username};
}

sub password {
    my ($self, $password) = @_;
    if (defined($password)) {
        $self->{password} = $password;
    }
    return $self->{password};
}

sub _agent {
    my ($self, $_agent) = @_;
    if (defined($_agent)) {
        $self->{_agent} = $_agent;
    }
    return $self->{_agent};
}

sub dryrun {
    my ($self, $dryrun) = @_;
    if (defined($dryrun)) {
        $self->{dryrun} = $dryrun;
    }
    return $self->{dryrun};
}

sub connect {
    my ($self) = @_;

    my $url = $self->url() || die "Missing url";
    my $apiKey = $self->apiKey() || die "Missing apiKey";

    my $c = Redmine::API->new(
    'auth_key' => $apiKey,
    base_url => $url,
    trace => 1);

    $self->_agent($c);
}

sub exportTask {
    my ($self, $task) = @_;

    unless ($task->id) {
        die "Can't export task without id";
    }

    # Extract the issue code
    my $issueCode = undef;
    if ($task->id =~ ISSUE_CODE) {
        $issueCode = $1;
    } elsif ($task->name =~ ISSUE_CODE) {
        $issueCode = $1;
    } elsif ($task->category =~ ISSUE_CODE) {
        $issueCode = $1;
    } elsif ($task->description =~ ISSUE_CODE) {
        $issueCode = $1;
    }

    unless ($issueCode) {
        die "Can't export task without issue code";
    }

    # Convert to Redmine issue id
    my $issueId = $self->_issueId($issueCode);

    unless ($issueId) {
        die "Can't find Redmine issue id for $issueCode";
    }

    my $date = _formatDate($task->date, $task->start);
    my $time = _formatTime($task->time);
    my $description = $task->description;

    $self->_logWork($issueId, $date, $time, $description);
}

sub _issueId(){
    my ($self, $issueCode) = @_;

    $issueCode =~ s/^T//;
    $issueCode =~ s/.*-//;

    return $issueCode;
}

sub _logWork {
    my ($self, $issueId, $date, $time, $comment) = @_;

    die "Missing issue id" unless ($issueId);
    die "Missing date" unless ($date);
    die "Missing time" unless ($time);

    my $_agent = $self->_agent || die "Missing agent";

    print "[DEBUG] Logging work: '$issueId', '$date', '$time', '$comment'\n";

    if ($self->dryrun()) {
        die "DRYRUN: not exporting";
    }

    $_agent->time_entries->time_entry->create(
        issue_id => $issueId,
        spent_on => $date,
        activity_id => 8,
        hours => $time,
        comments => $comment,
        'done' => 90
    );
}

sub _formatDate {
    my ($date, $start) = @_;

    my $year = substr($date, 0, 4);
    my $month = substr($date, 5, 2);
    my $day = substr($date, 8, 2);

    return $year.'-'.$month.'-'.$day;
}

sub _formatTime {
    my ($time, $factor) = @_;

    $factor = 0.1 unless (defined($factor));

    my $lpart = int($time);
    my $rpart = ($time - $lpart);

    $rpart = $rpart / $factor;
    $rpart = sprintf( "%.0f", int($rpart + .5 * ($rpart <=> 0)) );
    $rpart = $rpart * 100 * $factor;

    if ($rpart >= 100) {
        $lpart += 1;
        $rpart = 0;
    }

   return sprintf("%d.%02dh", $lpart, $rpart);
}

1;

