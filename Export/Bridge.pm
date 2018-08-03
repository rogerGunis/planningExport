package Export::Bridge;

use strict;

use fields qw(config planner connector);
use Data::Dumper;

require Export::Planner;
require Export::Connector;

sub new {
    my ($class) = @_;
    return fields::new($class);
}

sub config {
    my ($self, $config) = @_;
    if (defined($config)) {
        $self->{config} = $config;
    }
    return $self->{config};
}

sub planner {
    my ($self, $planner) = @_;
    if (defined($planner)) {
        $self->{planner} = $planner;
    }
    return $self->{planner};
}

sub connector {
    my ($self, $connector) = @_;
    if (defined($connector)) {
        $self->{connector} = $connector;
    }
    return $self->{connector};
}

# Export without confirmation
sub export {
    my ($self, $fromDate, $toDate) = @_;
    $self->exportTasks($self->pendingTasks($fromDate, $toDate));
}

sub pendingTasks {
    my ($self, $fromDate, $toDate) = @_;

    my $config = $self->config() || die "Missing config";
    my $planner = $self->planner() || die "Missing planner";

    my $tasks = $planner->tasks($fromDate, $toDate);

    unless (scalar(@$tasks)) {
        die "There is no activity between ".
            ($fromDate ? $fromDate : "the start")." and ".
            ($toDate ? $toDate : "today");
    }

    # Only keep the tasks that have not been exported
    my $exportedIds = $config->get('exportedIds');
    $tasks = $self->_retain($tasks, $exportedIds);

    unless (scalar(@$tasks)) {
        die "There is no activity to export between ".
            ($fromDate ? $fromDate : "the start")." and ".
            ($toDate ? $toDate : "today");
    }

    return $tasks;
}

sub showProjects {
    my ($self, $project,$searchSummary) = @_;
    my $connector = $self->connector() || die "Missing connector";
    $connector->connect();

    eval {
        $connector->showProjects();
    };
    if ($@) {
        print STDERR "[ERROR] Projects not listed': $@"."\n";
    }
}

sub exportIssues {
    my ($self, $project,$searchSummary) = @_;

    my $config = $self->config() || die "Missing config";
    my $connector = $self->connector() || die "Missing connector";

    # Connect once here instead of print one error message per task
    $connector->connect();

    my $issues = undef;
      eval {
          $issues = $connector->exportIssues($project,$searchSummary);
      };
      if ($@) {
          print STDERR "[WARN] Exporting issues not possible': $@"."\n";
      }
      my $width = 60;
    foreach my $issue (@$issues){
      print $issue->{'Key'}."\t".sprintf("%".$width."s", substr($issue->{'Summary'},0,$width))." \t ".$issue->{'url'}."\n"; }
}

sub exportTasks {
    my ($self, $tasks) = @_;

    my $config = $self->config() || die "Missing config";
    my $connector = $self->connector() || die "Missing connector";

    # Connect once here instead of print one error message per task
    $connector->connect();

    my $lastDate = $config->get('lastExportedDate');

    foreach my $task (@$tasks) {
        eval {
            $connector->exportTask($task);
            $config->push('exportedIds', $task->id());

            if (!$lastDate || $task->date() gt $lastDate) {
                $lastDate = $task->date();
            }
        };
        if ($@) {
            print STDERR "[WARN] Could not export '$task': $@"."\n";
        }
    }

    # Update the date of the last exported task
    if ($lastDate) {
        $config->set('lastExportedDate', $lastDate);
    }

    $config->save();
}

sub _retain {
    my ($self, $tasks, $ids) = @_;

    my @keep;
    foreach my $task (@$tasks) {
        my $id = $task->id();
        unless (grep(/^$id$/, @$ids)) {
            push @keep, $task;
        }
    }

    return \@keep;
}

1;
