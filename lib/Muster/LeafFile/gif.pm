package Muster::LeafFile::gif;

#ABSTRACT: Muster::LeafFile::gif - a GIF file in a Muster content tree
=head1 NAME

Muster::LeafFile::gif - a GIF file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a GIF file.

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

    # There are multiple fields which could be used as an image "description".
    # Check through them until you find a non-empty one.
    my $description = '';
    foreach my $field (qw(Caption-Abstract Comment ImageDescription UserComment))
    {
        if (exists $info->{field} and $info->{$field} and !$description)
        {
            $description = $info->{field};
        }
    }
    $meta->{description} = $description if $description;

    # Use a consistent naming for tag fields.
    if (exists $info->{Keywords} and $info->{Keywords})
    {
        $meta->{tags} = $info->{Keywords};
    }

    # There are SOOOOOO many fields in EXIF data, just remember
    # the ones which I am interested in.
    foreach my $field (qw(Artist CreateDate DateTimeOriginal FileSize ImageHeight ImageSize ImageWidth Megapixels))
    {
        if ($info->{$field})
        {
            $meta->{$field} = $info->{$field};
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

