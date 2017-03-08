package Muster::Leaf::File;

#ABSTRACT: Muster::Leaf::File - a file in a Muster content tree
=head1 NAME

Muster::Leaf::File - a file in a Muster content tree

=head1 SYNOPSIS

    use Muster::Leaf::File;
    my $file = Muster::Leaf::File->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.

=cut

use Mojo::Base 'Muster::Leaf';

use Carp;
use Mojo::Util      'decode';
use File::Basename 'basename';
use YAML::Any;
use Lingua::EN::Titlecase;

has filename   => sub { croak 'no filename given' };
has name       => sub { shift->build_name };
has pagetype   => sub { shift->build_pagetype };
has ext        => sub { shift->build_ext };
has pagename   => sub { shift->build_pagename };

=head2 reclassify

Reclassify this object as a Muster::Leaf::File subtype.
If a subtype exists, cast to that subtype and return the object;
if not, return undef.
To simplify things, pagetypes are determined by the file extension,
and the object name will be Muster::Leaf::File::$pagetype

=cut

sub reclassify {
    my $self = shift;

    my $pagetype = $self->pagetype;
    my $subtype = __PACKAGE__ . "::" . $pagetype;
    my $has_subtype = eval "require $subtype;"; # needs to be quoted because $subtype is a variable
    if ($has_subtype)
    {
        $subtype->import();
        return bless $self, $subtype;
    }
    else
    {
        $subtype = __PACKAGE__ . "::NONE";
        $has_subtype = eval "require $subtype;";
        if ($has_subtype)
        {
            $subtype->import();
            $self->{pagetype} = 'NONE';
            return bless $self, $subtype;
        }
    }
    return undef;
}

sub build_name {
    my $self = shift;

    # get last filename part
    my $base = basename($self->filename);

    # delete suffix
    $base =~ s/\.\w+$//;

    return $base;
}

sub build_pagename {
    my $self = shift;

    # build from parent_page, infix slash and name
    return join '/' => grep {$_ ne ''} $self->parent_page, $self->name;
}

sub build_pagetype {
    my $self = shift;

    my $ext = '';
    if ($self->filename =~ /\.(\w+)$/)
    {
        $ext = $1;
    }
    return $ext;
}

sub build_ext {
    my $self = shift;

    my $ext = '';
    if ($self->filename =~ /\.(\w+)$/)
    {
        $ext = $1;
    }
    return $ext;
}

sub build_raw {
    my $self = shift;

    # open file for decoded reading
    my $fn = $self->filename;
    open my $fh, '<:encoding(UTF-8)', $fn or croak "couldn't open $fn: $!";

    # slurp
    return do { local $/; <$fh> };
}

sub build_meta {
    my $self    = shift;

    # there is always the default information
    # of pagename, filename etc.
    my $meta = {
        pagename=>$self->pagename,
        parent_page=>$self->parent_page,
        filename=>$self->filename,
        pagetype=>$self->pagetype,
        name=>$self->name,
        title=>$self->derive_title,
    };

    return $meta;
}

sub derive_title {
    my $self = shift;

    # get the title from the name of the file
    my $name = $self->name;
    $name =~ s/_/ /g;
    my $tc = Lingua::EN::Titlecase->new($name);
    return $tc->title();
}

sub build_html {
    my $self = shift;
    
    croak 'build_html needs to be overwritten by subclass';
}

1;

__END__

