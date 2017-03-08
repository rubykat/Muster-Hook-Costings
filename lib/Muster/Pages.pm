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

use YAML::Any;
use POSIX qw(ceil);
use Mojo::URL;
use Hash::Merge;
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
    foreach my $psp (@{$self->page_sources()})
    {
        my $type = $psp->{type};
        my $obj = $type->new(
            parent_page=>'',
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

Find a page in the pagestores.

=cut

sub find {
    my $self = shift;
    my $pagename = shift;

    # split pagename and find content node
    my @names = split m|/| => $pagename;

    my $node = undef;
    my $i = 0;
    # go through each page-source until we find the page
    while (!$node && $i < scalar @{$self->{_sources}})
    {
        my $top_node = $self->{_sources}[$i];
        $node = $top_node->find(@names);
        $i++;
    }

    return undef unless $node;

    # the node could be a Leaf or a PageStore; we want a Leaf
    my $node_type = ref $node;
    if ($node_type =~ /PageStore/)
    {
        $node = $node->leaf;
    }

    return $node;
} # find

=head2 all_pages

Get all the known pages; page + meta.
Return a hash where the keys are the pagenames

=cut

sub all_pages {
    my $self = shift;

    my $all_pages = {};
    my $merge = Hash::Merge->new('LEFT_PRECEDENT');
    # Go through all the sources
    # Earlier sources take precedence
    for (my $i = 0; $i < scalar @{$self->{_sources}}; $i++)
    {
        my $top_node = $self->{_sources}[$i];
        my $pages = $top_node->get_all_meta(1);
        my $new_pages = $merge->merge($all_pages, $pages);
        $all_pages = $new_pages;
    }

    return $all_pages;
} # all_pages

=head1 Helper Functions

These are functions which are NOT exported by this plugin.

=cut

1; # End of Muster::Pages
__END__
