#!/usr/bin/perl
use strict;

use File::Basename;
use lib dirname($0);

use Getopt::Long;
use Pod::Usage;

require Export::Configuration;
require Export::FrontEnd;
require Export::Bridge;
require Export::Planner::Hamster;
require Export::Connector::Redmine;

use constant HAMSTER_DB =>
    $ENV{'HOME'}.'/.local/share/hamster-applet/hamster.db';

my $lockFile;
eval {
    my $database    = HAMSTER_DB;
    my $redmineUrl  = undef;
    my $apiKey      = undef;
    my $fromDate    = undef;
    my $toDate      = undef;
    my $dryrun      = 0;
    my $help        = 0;
    my $man         = 0;

    if (!GetOptions(
        'database|d=s' => \$database,
        'redmine|r=s'     => \$redmineUrl,
        'apiKey|a=s' => \$apiKey,
        'from|f=s'     => \$fromDate,
        'to|t=s'       => \$toDate,
        'dryrun'       => \$dryrun,
        'help|?'       => \$help,
        'man'          => \$man)) {
        pod2usage(2);
    } elsif ($help) {
        pod2usage(1);
    } elsif ($man) {
        pod2usage(-exitstatus => 0, -verbose => 2);
    }

    my $config = new Export::Configuration('hamsterToRedmine');

    $lockFile = $config->file().'.lock';
    if (-e $lockFile) {
        Export::FrontEnd->alert("ERROR: The process is already running Lockfile <".$lockFile.">!");
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

    # Prompt for the starting date if it is missing
    unless ($fromDate) {
        my $lastDate = $config->get('lastExportedDate');
        $fromDate = Export::FrontEnd->prompt("Export from:", $lastDate);
    }

    my $tasks = $bridge->pendingTasks($fromDate, $toDate);

    if (Export::FrontEnd->confirmExport($tasks, $fromDate, $toDate)) {
        # Prompt for missing connection details
        unless ($redmineUrl) {
            my $lastUrl = $config->get('url');
            $redmineUrl = Export::FrontEnd->prompt("redmine URL:", $lastUrl);
        }

        unless ($apiKey ) {
            ($apiKey) =
                Export::FrontEnd->promptPassword("Login to redmine");
        }

        my $redmine = new Export::Connector::Redmine(
            'config' => $config,
            'url' => $redmineUrl,
            'apiKey' => $apiKey,
            'dryrun' => $dryrun
        );

        $bridge->connector($redmine);

        $bridge->exportTasks($tasks);
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

hamsterToredmine.pl - Export time tracked with Hamster to redmine.

=head1 SYNOPSIS

perl hamsterToredmine.pl
[-d|--database I<path>]
[-r|--redmine I<url>]
[-a|--apiKey <apiKey>]
[-f|--from I<YYYY-MM-DD>]
[-t|--to I<YYYY-MM-DD>]
[--dryrun]
[--help]

=head1 DESCRIPTION 

=over 8

=item B<-d> I<path>, B<--database> I<path>

Path to the Hamster SQLite database (defaults to I<~/.local/share/hamster-applet/hamster.db>).

=item B<-r> I<url>, B<--redmine> I<url>

URL pointing to redmine home page (e.g. I<http://redmine.mycompany.com:8080>). If not supplied, thr URL of the last export is used.

=item B<-a> I<apiKey>, B<--apiKey> I<apiKey>

redmine apiKey - Look in your settings in redmine to get it

=item B<-f> I<YYYY-MM-DD>, B<--from> I<YYYY-MM-DD>

Date to export the activity from. If not supplied, the date of the last exported activity is used. 

=item B<-t> I<YYYY-MM-DD>, B<--to> I<YYYY-MM-DD>

Date to export the activity from. If not supplied, the current date is used.

=item B<--dryrun>

Do not export the tasks to redmine.

=item B<--help>

Print a brief help message and exits.

=back

This script prompts the user for missing arguments (redmine connection details, start date). If Zenity is available, the command line prompts are replaced with dialog boxes.

Exported tasks are stored in a configuration file, to avoid exporting them multiple times. To force the export again, edit or delete the configuration file, located at I<~/.config/planningExport/hamsterToredmine>.

=head1 SEE ALSO

Hamster project site: http://projecthamster.wordpress.com

=cut

