#!/usr/bin/perl
use strict;

use File::Basename;
use lib dirname($0);

use Getopt::Long;
use Pod::Usage;
use Data::Dumper;

require Export::Configuration;
require Export::FrontEnd;
require Export::Bridge;
require Export::Planner::Hamster;
require Export::Connector::JIRA;

use constant HAMSTER_DB =>
    $ENV{'HOME'}.'/.local/share/hamster-applet/hamster.db';

my $lockFile;
eval {
    my $database     = HAMSTER_DB;
    my $jiraUrl      = undef;
    my $jiraUsername = undef;
    my $jiraPassword = undef;
    my $displayUrl = undef;
    my $fromDate     = undef;
    my $toDate       = undef;
    my $exportIssuesFromProject   = undef;
    my $searchSummary = undef;
    my $showProjects = undef;
    my $dryrun       = 0;
    my $help         = 0;
    my $man          = 0;

    if (!GetOptions(
        'database|d=s' => \$database,
        'jira|j=s'     => \$jiraUrl,
        'username|u=s' => \$jiraUsername,
        'password|p=s' => \$jiraPassword,
        'displayUrl|y=s' => \$displayUrl,
        'from|f=s'     => \$fromDate,
        'to|t=s'       => \$toDate,
        'dryrun'       => \$dryrun,
        'showProjects|x'       => \$showProjects,
        'exportIssuesFromProject|l=s'         => \$exportIssuesFromProject,
        'searchSummary|s=s'         => \$searchSummary,
        'help|?'       => \$help,
        'man'          => \$man)) {
        pod2usage(2);
    } elsif ($help) {
        pod2usage(1);
    } elsif ($man) {
        pod2usage(-exitstatus => 0, -verbose => 2);
    }

    my $config = new Export::Configuration('hamsterToJIRA');

    $lockFile = $config->file().'.lock';
    if (-e $lockFile) {
        Export::FrontEnd->alert("ERROR: The process is already running <".$lockFile.">!");
        exit(1);
    } else {
        open FILE, ">$lockFile";
        close FILE;
    }

    my $bridge = new Export::Bridge();
    $bridge->config($config);

    my $hamster = new Export::Planner::Hamster();
    $hamster->database($database);
    $bridge->planner($hamster);

    # Prompt for missing connection details
    unless ($jiraUrl) {
        my $lastUrl = $config->get('url');
        $jiraUrl = Export::FrontEnd->prompt("JIRA URL:", $lastUrl);
    }

    unless ($jiraUsername && $jiraPassword) {
        ($jiraUsername, $jiraPassword) =
            Export::FrontEnd->promptPassword("Login to JIRA");
    }

    chomp($jiraPassword);
    chomp($jiraUsername);
    chomp($displayUrl);

    # pre initialization - after this no actual connection is made
    my $jira = new Export::Connector::JIRA();
    $jira->config($config);
    $jira->url($jiraUrl);
    $jira->username($jiraUsername);
    $jira->password($jiraPassword);
    $jira->dryrun($dryrun);
    $bridge->connector($jira);


    if($exportIssuesFromProject){
      $bridge->exportIssues($exportIssuesFromProject,$searchSummary,$displayUrl);
    }
    elsif($showProjects){
      $bridge->showProjects($exportIssuesFromProject,$searchSummary);
    }
    else{
      # Prompt for the starting date if it is missing
      unless ($fromDate) {
          my $lastDate = $config->get('lastExportedDate');
          $fromDate = Export::FrontEnd->prompt("Export from:", $lastDate);
      }

      my $tasks = $bridge->pendingTasks($fromDate, $toDate);

      if (Export::FrontEnd->confirmExport($tasks, $fromDate, $toDate)) {
          $bridge->exportTasks($tasks);
      }
    }

};
if ($@) {
    Export::FrontEnd->alert("ERROR: $@");
}
if ($lockFile) {
    unlink $lockFile;
}

__END__

=head1 NAME

hamsterToJIRA.pl - Export time tracked with Hamster to JIRA.

=head1 SYNOPSIS

perl hamsterToJIRA.pl
[-d|--database I<path>]
[-j|--jira I<url>]
[-u|--username I<username>]
[-p|--password I<password>]
[-f|--from I<YYYY-MM-DD>]
[-t|--to I<YYYY-MM-DD>]
[-l|--exportIssuesFromProject (CurrentSprint) I<ProjectId>]
[-s|--searchSummary I<text>]
[-x|--showProjects]
[--dryrun]
[--help]

=head1 DESCRIPTION 

=over 8

=item B<-d> I<path>, B<--database> I<path>

Path to the Hamster SQLite database (defaults to I<~/.local/share/hamster-applet/hamster.db>).

=item B<-j> I<url>, B<--jira> I<url>

URL pointing to JIRA home page (e.g. I<http://jira.mycompany.com:8080>). If not supplied, thr URLbof the last export is used.

=item B<-u> I<username>, B<--username> I<username>

JIRA connection login.

=item B<-p> I<password>, B<--password> I<password>

JIRA connection password.

=item B<-f> I<YYYY-MM-DD>, B<--from> I<YYYY-MM-DD>

Date to export the activity from. If not supplied, the date of the last exported activity is used. 

=item B<-t> I<YYYY-MM-DD>, B<--to> I<YYYY-MM-DD>

Date to export the activity from. If not supplied, the current date is used.

=item B<-l> I<exportIssuesFromProject>

Returns a list of key <=> Summary of a given project (open sprint and issue not closed) (see -s)

=item B<-s> I<searchSummary>

Searches for summary in a given project (see -l)


=item B<--dryrun>

Do not export the tasks to JIRA.

=item B<--help>

Print a brief help message and exits.

=back

This script prompts the user for missing arguments (JIRA connection details, start date). If Zenity is available, the command line prompts are replaced with dialog boxes.

Exported tasks are stored in a configuration file, to avoid exporting them multiple times. To force the export again, edit or delete the configuration file, located at I<~/.config/planningExport/hamsterToJIRA>.

=head1 SEE ALSO

Hamster project site: http://projecthamster.wordpress.com

=cut

