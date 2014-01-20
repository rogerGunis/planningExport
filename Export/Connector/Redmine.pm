package Export::Connector::Redmine;

use Data::Dumper;
use strict;
use base qw(Export::Connector);
use fields qw(config url username password dryrun _agent apiKey activityHash);

# see http://search.cpan.org/~celogeek/Redmine-API-0.03/lib/Redmine/API.pm
use Redmine::API;
use Redmine::API::Request;
use Redmine::API::Action;

use constant ISSUE_CODE => qr/^((T\d+)|[a-zA-Z0-9_]{2,}-\d+)/;

=head3 method new

   Set keys
=cut
sub new {
    my $class = shift;
    my %opt = @_; 

    my $self = fields::new($class);


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

sub activities {

    my ($self, $activityHash) = @_;

    if (defined($activityHash)) {
        $self->{activityHash} = $activityHash;
    }
    return $self->{activityHash};
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

=head3 method getActivities

    get and store activityIndex as Hash
=cut
sub _getActivities {
    my $self = shift;

    my $api = Redmine::API->new(
        'auth_key' => $self->apiKey(),
        base_url => $self->url(),
        trace => 0
    );

    my $request = Redmine::API::Request->new(
    'api' => $api,
    route => 'enumerations/time_entry_activities');

    my $actIds = Redmine::API::Action->new(
        'request' => $request,
        'action' => 'get'
    );

    my $activities = $actIds->all();

    my $activityHash = {};
    foreach my $activityEntry (@{$activities->body->{time_entry_activities}}){
        $activityHash->{$activityEntry->{'name'}} = $activityEntry->{'id'};
    }

    $self->activities($activityHash);

}

sub connect {
    my ($self) = @_;

    my $url = $self->url() || die "Missing url";
    my $apiKey = $self->apiKey() || die "Missing apiKey";

    my $c = Redmine::API->new(
        'auth_key' => $apiKey,
        base_url => $url,
        trace => 0
    );

    $self->_agent($c);

    $self->_getActivities();
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

    $self->_logWork($issueId, $date, $time, $description, $task->category);
}

sub _issueId(){
    my ($self, $issueCode) = @_;

    $issueCode =~ s/^T//;
    $issueCode =~ s/.*-//;

    return $issueCode;
}

sub _logWork {
    my ($self, $issueId, $date, $time, $comment, $category) = @_;

    die "Missing issue id" unless ($issueId);
    die "Missing date" unless ($date);
    die "Missing time" unless ($time);

    my $_agent = $self->_agent || die "Missing agent";

    my $activityId = $self->activities()->{$category} || undef;

    print "[DEBUG] Logging work: '$issueId', '$category ($activityId)', '$date', '$time', '$comment'\n";

    if($activityId){

        if ($self->dryrun()) {
            die "DRYRUN: not exporting Task with comment: <$comment>";
        }

        $_agent->time_entries->time_entry->create(
            issue_id => $issueId,
            spent_on => $date,
            activity_id => $activityId,
            hours => $time,
            comments => $comment,
            'done' => 90
        );
    }
    else{
        print '[WARN] Logging work: Category not found <'.$category."> skipping\n";
    }
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

