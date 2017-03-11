package Muster::Leaf::File::txt;

#ABSTRACT: Muster::Leaf::File::txt - a plain text file in a Muster content tree
=head1 NAME

Muster::Leaf::File::txt - a plain text file in a Muster content tree

=head1 SYNOPSIS

    use Muster::Leaf::File;
    my $file = Muster::Leaf::File->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a plain text file.

=cut

use Mojo::Base 'Muster::Leaf::File';

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

