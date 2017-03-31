package Muster::LeafFile::txt;

#ABSTRACT: Muster::LeafFile::txt - a plain text file in a Muster content tree
=head1 NAME

Muster::LeafFile::txt - a plain text file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a plain text file.

=cut

use Mojo::Base 'Muster::LeafFile';

use Carp;
use Mojo::Util      'decode';
use YAML::Any;

sub is_this_a_page {
    my $self = shift;

    return 1;
}

sub build_html {
    my $self = shift;

    my $content = $self->cooked();
    return <<EOT;
<pre>
$content
</pre>
EOT

}

sub build_meta {
    my $self = shift;

    my $meta = $self->SUPER::build_meta();

    # add the wordcount to the default meta
    $meta->{wordcount} = $self->wordcount;

    return $meta;
}

sub wordcount {
    my $self = shift;

    if (!exists $self->{wordcount})
    {
        my $content = $self->raw();

        # count the words in the content
        $content =~ s/<[^>]+>/ /gs; # remove html tags
        # Remove everything but letters + spaces
        # This is so that things like apostrophes don't make one
        # word count as two words
        $content =~ s/[^\w\s]//gs;

        my @matches = ($content =~ m/\b[\w]+/gs);
        $self->{wordcount} = scalar @matches;
    }

    return $self->{wordcount};
} # wordcount
1;

__END__

