package Muster::LeafFile::jpg;

#ABSTRACT: Muster::LeafFile::jpg - a JPEG file in a Muster content tree
=head1 NAME

Muster::LeafFile::jpg - a JPEG file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a JPEG file.

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

    # There are SOOOOOO many fields in EXIF data, just remember
    # the ones which I am interested in.
    foreach my $field (qw(Artist CameraType Caption-Abstract Comment CreateDate DateTimeOriginal FileSize Flash FocalLength ISO ImageDescription ImageHeight ImageSize ImageWidth ShutterSpeed UserComment))
    {
        # sqlite doesn't like column names with dashes in them
        my $newfield = $field;
        $newfield =~ s/-/_/g;
        if ($info->{$field})
        {
            $meta->{$newfield} = $info->{$field};
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

