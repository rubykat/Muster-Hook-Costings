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
has pagetype   => sub { shift->build_pagetype };
has name       => sub { shift->build_name };
has extension  => sub { shift->build_ext };
has pagename   => sub { shift->build_pagename };

=head2 reclassify

Reclassify this object as a Muster::Leaf::File subtype.
If a subtype exists, cast to that subtype and return the object;
if not, return self.
To simplify things, pagetypes are determined by the file extension,
and the object name will be Muster::Leaf::File::$pagetype

=cut

sub reclassify {
    my $self = shift;

    my $pagetype = $self->pagetype;
    if ($pagetype)
    {
        my $subtype = __PACKAGE__ . "::" . $pagetype;
        eval "require $subtype;"; # needs to be quoted because $subtype is a variable
        $subtype->import();
        return bless $self, $subtype;
    }
    return $self;
}

sub build_name {
    my $self = shift;

    # get last filename part
    my $base = basename($self->filename);

    # if this is a page as opposed to a non-page, delete the suffix
    if ($self->pagetype)
    {
        # delete suffix
        $base =~ s/\.\w+$//;
    }

    return $base;
}

sub build_pagename {
    my $self = shift;

    # build from parent_page, infix slash and name
    return join '/' => grep {$_ ne ''} $self->parent_page, $self->name;
}

sub build_pagetype {
    my $self = shift;

    my $file=$self->filename;

    # the extension is the pagetype only if there exists a Muster::Leaf::File::*ext* module for it.
    if ($file =~ /\.([^.]+)$/) {
        my $pt = $1;
        my $subtype = __PACKAGE__ . "::" . $pt;
        my $has_pagetype = eval "require $subtype;"; # needs to be quoted because $subtype is a variable
        return $pt if $has_pagetype;
    }
    return '';
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
        extension=>$self->extension,
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

# this is the default for non-pages
sub build_html {
    my $self = shift;
    
    my $link = $self->pagename();
    my $title = $self->derive_title();
    return <<EOT;
<h1>$title</h1>
<p>
<a href="/$link">$link</a>
</p>
EOT

}

1;

__END__

