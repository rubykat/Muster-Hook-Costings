package Muster::Leaf::File::NonPage;

#ABSTRACT: Muster::Leaf::File::NonPage - an unknown file
=head1 NAME

Muster::Leaf::File::NonPage - an unknown file

=head1 SYNOPSIS

    use Muster::Leaf::File;
    my $file = Muster::Leaf::File->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is an unknown file.

=cut

use Mojo::Base 'Muster::Leaf::File';

use Carp;
use YAML::Any;
use File::Basename 'basename';

sub build_html {
    my $self = shift;

    my $ext = '';
    if ($self->filename =~ /\.(\w+)$/)
    {
        $ext = $1;
    }
    my $link = $self->pagename() . ($ext ? ".${ext}" : '');
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

