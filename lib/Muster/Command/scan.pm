package Muster::Command::scan;

#ABSTRACT: Muster::Command::scan - scan pages for metadata
=head1 NAME

Muster::Command::scan - scan pages for metadata

=head1 DESCRIPTION

Content management system - scan pages for metadata

=cut

use Mojo::Base 'Mojolicious::Command';
use Muster::Scanner;

has description => 'Scans the known pages to collect their metadata; if no arguments, scans all pages';
has usage       => "Usage: APPLICATION scan [page] ...\n";

sub run {
    my ($self, @args) = @_;

    my $scanner = Muster::Scanner->new(command=>$self);
    $scanner->init();
    if (scalar @args)
    {
        $scanner->scan_some_pagefiles(@args);
    }
    else
    {
        $scanner->scan_all();
    }
}

1;

