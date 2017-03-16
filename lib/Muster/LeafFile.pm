package Muster::LeafFile;

#ABSTRACT: Muster::LeafFile - a file in a Muster content tree
=head1 NAME

Muster::LeafFile - a file in a Muster content tree

=head1 SYNOPSIS

    use Muster::LeafFile;
    my $file = Muster::LeafFile->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a content tree.

=cut

use Mojo::Base -base;

use Carp;
use Mojo::Util      'decode';
use File::Basename 'basename';
use YAML::Any;
use Lingua::EN::Titlecase;

has pagename    => '';
has parent_page => '';
has name        => sub { shift->build_name };
has title       => sub { shift->build_title };
has filename   => sub { croak 'no filename given' };
has pagetype   => sub { shift->build_pagetype };
has extension  => sub { shift->build_ext };
has pagename   => sub { shift->build_pagename };

=head2 raw

The raw content.

=cut
sub raw {
    my $self = shift;
    if (!exists $self->{raw})
    {
        $self->{raw} = $self->build_raw();
    }
    return $self->{raw};
}

=head2 cooked

The "cooked" (processed) content.

=cut
sub cooked {
    my $self = shift;
    my $new_content = shift;
    if (defined $new_content)
    {
        $self->{cooked} = $new_content;
    }
    elsif (!exists $self->{cooked})
    {
        $self->{cooked} = $self->raw;
    }
    return $self->{cooked};
}

=head2 html

HTML generation.

=cut
sub html {
    my $self = shift;
    if (!exists $self->{html})
    {
        $self->{html} = $self->build_html();
    }
    return $self->{html};
}

=head2 meta

Get the meta-data from the file.

=cut
sub meta {
    my $self = shift;
    if (!exists $self->{meta})
    {
        $self->{meta} = $self->build_meta();
    }
    return $self->{meta};
}

=head2 decache

Removed the cached information.
I'm not sure we still need to do this?

=cut
sub decache {
    my $self = shift;
    
    delete $self->{raw};
    delete $self->{html};
    delete $self->{meta};
}

=head2 build_title

Build the title for this page.

=cut
sub build_title {
    my $self = shift;

    # try to extract title
    return $self->meta->{title} if exists $self->{meta} and exists $self->meta->{title};
    return $1 if defined $self->html and $self->html =~ m|<h1>(.*?)</h1>|i;
    return $self->name;
}

=head2 reclassify

Reclassify this object as a Muster::LeafFile subtype.
If a subtype exists, cast to that subtype and return the object;
if not, return self.
To simplify things, pagetypes are determined by the file extension,
and the object name will be Muster::LeafFile::$pagetype

=cut

sub reclassify {
    my $self = shift;

    my $pagetype = $self->pagetype;
    if ($pagetype)
    {
        my $subtype = __PACKAGE__ . "::" . $pagetype;
        eval "require $subtype;"; # needs to be quoted because $subtype is a variable
        $subtype->import();
        bless $self, $subtype;
        # initialize the meta data for this leaf, now that it knows how to parse it
        $self->meta();
        return $self;
    }
    return $self;
}

=head2 build_name

Build the base name of the related page.

=cut
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

=head2 build_pagename

Create the pagename from the filename.

=cut
sub build_pagename {
    my $self = shift;

    # build from parent_page, infix slash and name
    return join '/' => grep {$_ ne ''} $self->parent_page, $self->name;
}

=head2 build_pagetype

Derive the pagetype for this file, if it has a known module for it.
Otherwise, the pagetype is empty.

=cut
sub build_pagetype {
    my $self = shift;

    my $file=$self->filename;

    # the extension is the pagetype only if there exists a Muster::LeafFile::*ext* module for it.
    if ($file =~ /\.([^.]+)$/) {
        my $pt = $1;
        my $subtype = __PACKAGE__ . "::" . $pt;
        my $has_pagetype = eval "require $subtype;"; # needs to be quoted because $subtype is a variable
        return $pt if $has_pagetype;
    }
    return '';
}

=head2 build_ext

The file's extension.

=cut
sub build_ext {
    my $self = shift;

    my $ext = '';
    if ($self->filename =~ /\.(\w+)$/)
    {
        $ext = $1;
    }
    return $ext;
}

=head2 build_raw

The raw content of the file.

=cut
sub build_raw {
    my $self = shift;

    # open file for decoded reading
    my $fn = $self->filename;
    open my $fh, '<:encoding(UTF-8)', $fn or croak "couldn't open $fn: $!";

    # slurp
    return do { local $/; <$fh> };
}

=head2 build_meta

The meta-data extracted from the file.

=cut
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

=head2 derive_title

Derive the title without trying to create HTML.

=cut
sub derive_title {
    my $self = shift;

    # get the title from the name of the file
    my $name = $self->name;
    $name =~ s/_/ /g;
    my $tc = Lingua::EN::Titlecase->new($name);
    return $tc->title();
}

=head2 build_html

Create the default HTML for non-page.

=cut
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

