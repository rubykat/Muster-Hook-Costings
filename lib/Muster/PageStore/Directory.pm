package Muster::PageStore::Directory;

#ABSTRACT: Muster::PageStore::Directory - storing pages in a directory
=head1 NAME

Muster::PageStore::Directory - storing pages in a directory

=head1 SYNOPSIS

    use Muster::PageStore::Directory;
    my $dir = Muster::PageStore::Directory->new(
        filename => 'foo'
    );
    my $first_child = $dir->dir_children->[0];

=head1 DESCRIPTION

Directory PageStores represent directories in a Muster content tree.

=cut

use Mojo::Base 'Muster::PageStore';

use Muster::Leaf::File;
use List::Util  'first';
use Carp;
use File::Spec;
use File::Basename;
use YAML::Any;

has is_root     => undef;
has parent_node => undef;
has pages_dir   => sub { croak 'no pages_dir given' };
has filename   => sub { croak 'no filename given' };
has name       => sub { shift->build_name };
has path       => sub { shift->build_path };
has dir_children    => sub { shift->build_dir_children };
has file_children    => sub { shift->build_file_children };
has meta        => sub { shift->build_meta };
has html        => sub { shift->build_html };

sub init {
    my $self = shift;

    # check if the pages_dir exists
    my $pd = $self->pages_dir;
    my $pages_dir = File::Spec->rel2abs($pd);
    if (-d $pages_dir)
    {
        $self->{pages_dir} = $pages_dir;
        print STDERR "PAGES: ", $self->{pages_dir}, "\n";
    }
    else
    {
        croak "Pages dir '$pages_dir' not found!";
    }
}

sub build_name {
    my $self = shift;

    # root node
    return '' if $self->is_root;

    # get last filename part
    my $base = basename($self->filename);

    return $base;
}

sub build_path {
    my $self = shift;

    # root node
    return '' if $self->is_root;

    # build from path_prefix, infix slash and name
    return join '/' => grep {$_ ne ''} $self->path_prefix, $self->name;
}

sub build_dir_children {
    my $self = shift;

    my $dirname     = ($self->is_root ? $self->pages_dir : $self->filename);
    my @children    = ();

    # Iterate directory entries
    foreach my $entry (sort glob("$dirname/*"))
    {
        # add content directory node
        if (-d -r -x $entry)
        {
            my $node = Muster::PageStore::Directory->new(
                filename    => $entry,
                path_prefix => $self->path,
                parent_node => $self,
            );
            push @children, $node;
        }
    }
    return \@children;
}

sub build_file_children {
    my $self = shift;

    my $dirname     = ($self->is_root ? $self->pages_dir : $self->filename);
    my @children    = ();

    # Iterate directory entries
    foreach my $entry (sort glob("$dirname/*"))
    {
        # add content file node
        # We don't know if this file type is supported
        # until we make and init the object for it
        # since the tests for support are in the File module.
        if (-f -r $entry)
        {
            my $node = Muster::Leaf::File->new(
                filename    => $entry,
                path_prefix => $self->path,
                parent_node => $self,
            );
            $node = $node->reclassify();
            if ($node)
            {
                push @children, $node;
            }
        }
    }
    return \@children;
}

sub build_meta {
    my $self = shift;
    my %meta = ();

    # get meta information from 'index' node
    if (my $index = $self->find_index())
    {
        $meta{$_} = $index->meta->{$_} for keys %{$index->meta};
    }

    return \%meta;
}

sub build_html {
    my $self = shift;

    # try to find index
    my $index = $self->find_index();
    return unless $index;

    return $index->html;
}

sub find_index {
    my $self = shift;

    # The index file for a directory is either
    # * the "index" page below this directory
    # * the ${name}.mdwn page on the same level as this directory (if this is not root)
    my $index = $self->find_file_child('index');
    if (!$index and !$self->is_root)
    {
        my $name = $self->name;
        my $parent = $self->parent_node;
        if ($parent)
        {
            $index = $parent->find_file_child($name);
        }
    
    }
    return $index;
}

sub find_dir_child {
    my ($self, $name) = @_;
    return first {$_->name eq $name} @{$self->dir_children};
}

sub find_file_child {
    my ($self, $name) = @_;
    return first {$_->name eq $name} @{$self->file_children};
}

sub find {
    my ($self, @names) = @_;
    my $node = $self;

    # done
    return $node unless @names;

    # find matching child node
    my $name = shift @names;
    if (@names) # still more names left, we are looking for a directory
    {
        $node = $self->find_dir_child($name);
    }
    else # last one, could be a file or a directory
    {
        $node = $self->find_file_child($name);
        if (!$node)
        {
            $node = $self->find_dir_child($name);
        }
    }

    # couldn't find
    return unless $node;

    # continue search on child node
    return $node->find(@names);
}

sub get_all_meta {
    my $self = shift;

    my $merge = Hash::Merge->new();
    my $pages = {};

    # first, this directory/index
    my $index = $self->find_index();
    return unless $index;
    $pages->{$self->path} = $index->meta;

    # files below this
    for my $leaf (@{$self->file_children})
    {
        $pages->{$leaf->path} = $leaf->meta;
    }

    # directories below this
    for my $dir (@{$self->dir_children})
    {
        my $dir_pages = $dir->get_all_meta();
        my $new_pages = $merge->merge($pages,$dir_pages);
        $pages = $new_pages;
    }
    return $pages;
}

1;

__END__

