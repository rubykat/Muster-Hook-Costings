package Muster::Pages;

#ABSTRACT: Muster::Pages - looking after pages
=head1 NAME

Muster::Pages - looking after pages

=head1 SYNOPSIS

    use Muster::Pages;;

=head1 DESCRIPTION

Content Management System - looking after pages.
All pages here are file-based.
(We can worry about non-file-based pages some other time)

=cut

use Mojo::Base -base;
use Carp;

use Path::Tiny;
use YAML::Any;
use POSIX qw(ceil);
use Mojo::URL;
use Muster::Leaf;
use Muster::Leaf::File;
use Muster::PageStore;
use Muster::PageStore::Directory;

has page_sources => sub { croak "page_sources not defined" };

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;

    $self->{_sources} = [];
    foreach my $psp (@{$self->{page_sources}})
    {
        my $type = $psp->{type};
        my $obj = $type->new(
            path_prefix=>'',
            filename=>'',
            is_root=>1,
            %{$psp},
        );
        if (defined $obj and ref $obj eq $type)
        {
            # check if the object has an init method, and call it
            if ($obj->can('init'))
            {
                $obj->init();
            }
            push @{$self->{_sources}}, $obj;
        }
        else
        {
            die __PACKAGE__, " failed to create object $type ", Dump($obj), " from args ", Dump($psp);
        }
    }

    return $self;

} # init

=head2 find

Find a page.

=cut

sub find {
    my $self = shift;
    my $path = shift;

    # split path and find content node
    my @names = split m|/| => $path;

    my $node = undef;
    my $i = 0;
    # go through each page-source until we find the page
    while (!$node && $i < scalar @{$self->{_sources}})
    {
        my $top_node = $self->{_sources}[$i];
        $node = $top_node->find(@names);
        $i++;
    }

    return $node;
} # find

=head2 pagelist

List of all the pages.

=cut

sub pagelist {
    my $self = shift;
    my %args = @_;

} # pagelist

=head2 total_pages

Total number of pages.

=cut

sub total_pages {
    my $self = shift;
    my %args = @_;

} # total_pages

=head2 what_error

There was an error, what was it?

=cut

sub what_error {
    my $self = shift;
    my %args = @_;

    return $self->{error};
} # what_error

=head1 Helper Functions

These are functions which are NOT exported by this plugin.

=cut

1; # End of Muster::Pages
__END__
