package Export::Connector::JIRA;

use strict;
use base qw(Export::Connector);
use fields qw(config url username password dryrun _agent _projects);
use Encode qw(decode encode);

# use constant ISSUE_CODE => qr/^([a-zA-Z]{2,}-\d+)/;
use constant ISSUE_CODE => qr/^(_PROJECT_-\d+)/i;

use Data::Dumper;
use JIRA::REST;

sub new {
    my ($class) = @_;

    my $self = fields::new($class);

    return $self;
}

sub config {
    my ($self, $config) = @_;
    if (defined($config)) {
        $self->{config} = $config;
    }
    return $self->{config};
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

sub dryrun {
    my ($self, $dryrun) = @_;
    if (defined($dryrun)) {
        $self->{dryrun} = $dryrun;
    }
    return $self->{dryrun};
}

sub exportIssues {
    my ($self,$project,$searchSummary) = @_;

    my $jira = $self->{_agent};

    my $issues  = [];
    my $addSearchString = " and Sprint in openSprints() AND ( issuetype in standardIssueTypes() OR issuetype in subtaskIssueTypes())   and status not in (Closed,Done) ";
    if($searchSummary){
      $addSearchString = 'and summary ~ "'.$searchSummary.'"';
    }
    $addSearchString .= " ORDER BY RANK, issuetype";

    my $search = $jira->POST('/search', undef, {
        jql        => 'project = '.$project.' and (status != "resolved" and status != "closed") '.$addSearchString,
        startAt    => 0,
        maxResults => 300,
        fields     => [ qw/summary status issuetype parent/ ],
    });

    my $json = JSON->new->allow_nonref;

    foreach my $issue  (@{$search->{issues}}) {
      my $summary = encode('UTF-8',$issue->{'fields'}->{'summary'});
      my $isSubTask = $issue->{'fields'}->{'issuetype'}->{'subtask'};
      my $parentSummary = $issue->{'fields'}->{'parent'}->{'fields'}->{'summary'};

      push @$issues, {
        'Summary' => $summary,
        'parentSummary' => $parentSummary,
        'Key' => $issue->{'key'},
        'isSubTask' => "".$isSubTask,
        'url' => $self->url."/browse/".$issue->{'key'}
      }

    }

    return $issues;

}

sub showProjects {
    my ($self) = @_;

    my $projects  = [];
    push @$projects, map {($_->{'key'} )} @{$self->{_agent}->GET('/project'  )};

    $self->{_projects} = $projects;

    print 'All projects on Server: '."\n";
    foreach my $project (@$projects){
      print " ".$project."\n";
    }

    # $self->config()->set('_projects', \%projects);

}

sub connect {
    my ($self) = @_;

    my $url = $self->url() || die "Missing url";
    my $username = $self->username() || die "Missing username";
    my $password = $self->password() || die "Missing password";

    my $jira = JIRA::REST->new($url, $username, $password);
    $self->{_agent} = $jira;

    $self->config()->set('url', $url);
}

sub exportTask {
    my ($self, $task) = @_;

    unless ($task->id) {
        die "Can't export task without id";
    }

    # Extract the issue code
    my $issueCode = undef;

    my $projects  = [];
    push @$projects, map {($_->{'key'} )} @{$self->{_agent}->GET('/project'  )};

    $self->{_projects} = $projects;

    foreach my $project (@{$self->{_projects}}){

      my $ISSUE_CODE = ISSUE_CODE;
      $ISSUE_CODE =~ s/_PROJECT_/$project/;
      if ($task->id =~ $ISSUE_CODE) {
          $issueCode = $1;
      } elsif ($task->name =~ $ISSUE_CODE) {
          $issueCode = $1;
      } elsif ($task->category =~ $ISSUE_CODE) {
          $issueCode = $1;
      } elsif ($task->description =~ $ISSUE_CODE) {
          $issueCode = $1;
      }
    }

    unless ($issueCode) {
        die "Can't export task without issue code";
    }

    # Convert to JIRA issue id
    # my $issueId = $self->_issueId($issueCode);

    # unless ($issueId) {
    #     die "Can't find JIRA issue id for $issueCode";
    # }

    my $date = _formatDate($task->date, $task->start);
    my $time = _formatTime($task->time);
    my $description = $task->description;

    $self->_logWork($issueCode, $date, $time, $description, $task->category);
}

sub _issueId {
    my ($self, $issueCode) = @_;

    my $url = $self->url() || die "Missing url";

    my $issueIdCache = $self->config()->get('issueIdCache');

    my $issueId = $issueIdCache->{$issueCode};
    unless ($issueId) {
        my $response = $self->{_agent}->GET('/issue/' . $issueCode);
        my $issueId = $response->{'id'};

        # add to the id cache
        $self->config()->put('issueIdCache', $issueCode, $issueId);
    }

    return $issueId;
}

sub _logWork {
    my ($self, $issueCode, $date, $time, $comment, $category) = @_;

    die "Missing issueCode" unless ($issueCode);
    die "Missing date" unless ($date);
    die "Missing time" unless ($time);

    my $url = $self->url() || die "Missing url";

    print "[DEBUG] Logging work: '$issueCode', '$date', '$time', '$category: $comment'\n";

    if ($self->dryrun()) {
        die "DRYRUN: not exporting";
    }

    print STDERR "*** POSTING: issueCode='$issueCode', date='$date', time='$time', comment='$comment' ***\n";

    my $postResponse = $self->{_agent}->POST(
        '/issue/'.$issueCode.'/worklog',
        undef,
        { 'started'      => $date,
          'timeSpent'    => $time,
          'comment'      => decode('UTF-8', $category.': '.$comment, Encode::FB_CROAK)
         });
}

sub _formatDate {
    my ($date, $start) = @_;

    my $year = substr($date, 0, 4);
    my $month = substr($date, 5, 2);
    my $day = substr($date, 8, 2);

    # 2/Mar/14 11:40 PM
    $date = $year;
    $date .= '-'.sprintf('%02d',$month);
    $date .= '-'.sprintf('%02d',($day * 1));

    if ($start) {
        $date .= 'T'.$start.':00.000+0100';

        # my $hours = substr($start, 0, 2);
        # my $minutes = substr($start, 3, 2);
        # 1 AM -> 12 AM ; 1 PM -> 12 PM
        # if ($hours < 1) {
        #     $date .= ' '.($hours * 1).':'.$minutes.' PM';
        # } elsif ($hours < 13) {
        #     $date .= ' '.($hours * 1).':'.$minutes.' AM';
        # } else {
        #     $date .= ' '.($hours - 12).':'.$minutes.' PM';
        # }
    } else {
        $date .= ' 08:00 AM';
    }

    return $date;
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
    if($lpart == 0 && $rpart == 0){
      return sprintf("%d.%02dm", int($time*60));
    }
    else{
      return sprintf("%d.%02dh", $lpart, $rpart);
    }

}

1;

