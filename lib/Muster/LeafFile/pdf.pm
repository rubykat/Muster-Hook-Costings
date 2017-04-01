package Muster::LeafFile::pdf;

#ABSTRACT: Muster::LeafFile::pdf - a PDF file in a Muster content tree
=head1 NAME

Muster::LeafFile::pdf - a PDF file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a PDF file.

=cut

use Mojo::Base 'Muster::LeafFile';

use Carp;
use Mojo::Util      'decode';
use Encode qw{encode};
use Image::ExifTool qw(:Public);

# this is not a page
sub is_this_a_page {
    my $self = shift;

    return undef;
}

sub build_meta {
    my $self = shift;

    my $meta = $self->SUPER::build_meta();

    # What is in the EXIF overrides the defaults
    my $info = ImageInfo($self->filename);

    # Use a consistent naming for tag fields.
    # Combine the tag-like fields together.
    my @tags = ();
    foreach my $field (qw(Keywords Subject))
    {
        if (exists $info->{$field} and $info->{$field})
        {
            push @tags, $info->{$field};
        }
    }
    $meta->{tags} = join('|', @tags) if scalar @tags;

    # There are SOOOOOO many fields in EXIF data, just remember
    # the ones which I am interested in.
    foreach my $field (qw(Author CreateDate Description FileSize PageCount Title))
    {
        if ($info->{$field})
        {
            $meta->{lc($field)} = $info->{$field};
        }
    }

    return $meta;
}

sub build_raw {
    my $self = shift;

    return "";
}

sub build_html {
    my $self = shift;

    return "";
}

1;

__END__


