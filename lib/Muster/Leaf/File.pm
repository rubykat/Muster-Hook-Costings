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

has filename   => sub { croak 'no filename given' };
has name       => sub { shift->build_name };
has ext        => sub { shift->build_ext };
has path       => sub { shift->build_path };
has content    => sub { shift->build_content_and_meta->content };
has meta       => sub { shift->build_content_and_meta->meta };

=head2 reclassify

Reclassify this object as a Muster::Leaf::File subtype.
If a subtype exists, cast to that subtype and return the object;
if not, return undef.
To simplify things, subtypes are determined by the file extension,
and the object name will be Muster::Leaf::File::$ext

=cut

sub reclassify {
    my $self = shift;

    my $ext = $self->ext;
    my $subtype = __PACKAGE__ . "::" . $ext;
    my $has_subtype = eval "require $subtype;"; # needs to be quoted because $subtype is a variable
    if ($has_subtype)
    {
        $subtype->import();
        return bless $self, $subtype;
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

sub build_path {
    my $self = shift;

    # build from path_prefix, infix slash and name
    return join '/' => grep {$_ ne ''} $self->path_prefix, $self->name;
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

sub clear {
    my $self = shift;
}

sub build_raw {
    my $self = shift;

    # open file for decoded reading
    my $fn = $self->filename;
    open my $fh, '<:encoding(UTF-8)', $fn or croak "couldn't open $fn: $!";

    # slurp
    return do { local $/; <$fh> };
}

sub build_content_and_meta {
    my $self    = shift;

    croak 'build_content_and_meta needs to be overwritten by subclass';
}

sub build_html {
    my $self = shift;
    
    croak 'build_html needs to be overwritten by subclass';
}

1;

__END__

