package Muster::LeafFile::txt;

#ABSTRACT: Muster::LeafFile::txt - a plain text file in a Muster content tree
=head1 NAME

Muster::LeafFile::txt - a plain text file in a Muster content tree

=head1 SYNOPSIS

    use Muster::LeafFile;
    my $file = Muster::LeafFile->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a plain text file.

=cut

use Mojo::Base 'Muster::LeafFile';

use Carp;
use Mojo::Util      'decode';
use YAML::Any;

sub build_html {
    my $self = shift;

    my $content = $self->cooked();
    return <<EOT;
<pre>
$content
</pre>
EOT

}

1;

__END__

