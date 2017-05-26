package Muster::LeafFile::html;

#ABSTRACT: Muster::LeafFile::html - a HTML file in a Muster content tree
=head1 NAME

Muster::LeafFile::html - a HTML file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a HTML file.

=cut

use Mojo::Base 'Muster::LeafFile';

use Carp;
use YAML::Any;

sub is_this_a_page {
    my $self = shift;

    return 1;
}

sub build_html {
    my $self = shift;

    my $content = $self->cooked();
    return <<EOT;
$content
EOT

}

1;

__END__

