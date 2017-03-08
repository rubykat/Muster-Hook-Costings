package Muster::Scanner;

#ABSTRACT: Muster::Scanner - updating meta-data about pages
=head1 NAME

Muster::Scanner - updating meta-data about pages

=head1 DESCRIPTION

Content Management System
keeping meta-data about pages.

=cut

use Mojo::Base -base;
use Carp;
use Muster::MetaDb;
use Muster::Pages;
use YAML::Any;

has command => sub { croak "command is not defined" };

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;
    my $app = $self->command->app;

    $self->{pages} = Muster::Pages->new(page_sources => $app->config->{page_sources});
    $self->{pages}->init();
    $self->{metadb} = Muster::MetaDb->new(%{$app->config});
    $self->{metadb}->init();

    return $self;
} # init

=head2 scan_one_page

Scan a single page.

    $self->scan_one_page($page);

=cut

sub scan_one_page {
    my $self = shift;
    my $pagename = shift;

    my $app = $self->command->app;

    my $leaf = $self->{pages}->find($pagename);
    unless (defined $leaf)
    {
        warn __PACKAGE__, " scan_one_page page '$pagename' not found";
        return;
    }

    my $meta = $leaf->meta();
    unless (defined $meta)
    {
        warn __PACKAGE__, " scan_one_page meta for '$pagename' not found";
        return;
    }
    # add the meta to the metadb
    $self->{metadb}->update_one_page($pagename, %{$meta});

    print Dump($meta);

} # scan_one_page

=head2 delete_one_page

Delete a single page.

    $self->delete_one_page($page);

=cut

sub delete_one_page {
    my $self = shift;
    my $pagename = shift;

    my $app = $self->command->app;

    if ($self->{metadb}->delete_one_page($pagename))
    {
        print "DELETED: $pagename\n";
    }
    else
    {
        print "UNKNOWN: $pagename\n";
    }

} # delete_one_page

=head2 scan_all

Scan all pages.

=cut

sub scan_all {
    my $self = shift;
    my $app = $self->command->app;

    my $all_pages = $self->{pages}->all_pages();
    $self->{metadb}->update_all_pages(%{$all_pages});

    print "DONE\n";
} # scan_all

1; # End of Muster::Scanner
__END__
