package Muster::Leaf::File::mdwn;

#ABSTRACT: Muster::Leaf::File::mdwn - a Markdown file in a Muster content tree
=head1 NAME

Muster::Leaf::File::mdwn - a Markdown file in a Muster content tree

=head1 SYNOPSIS

    use Muster::Leaf::File;
    my $file = Muster::Leaf::File->new(
        filename => 'foo.md'
    );
    my $html = $file->html;

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a markdown file.

=cut

use Mojo::Base 'Muster::Leaf::File';

use Carp;
use Mojo::Util      'decode';
use Text::MultiMarkdown  'markdown';
use YAML::Any;

has content    => sub { shift->build_content_and_meta->content };
has meta       => sub { shift->build_content_and_meta->meta };

sub build_content_and_meta {
    my $self    = shift;
    my $content = $self->raw;
    my %meta    = ();

    # extract (and delete) meta data from file content
    $meta{lc $1} = $2
        while $content =~ s/\A(\w+):\s*(.*)[\n\r]+//;

    # done
    $self->content($content)->meta(\%meta);
}

sub build_html {
    my $self = shift;
    return markdown($self->raw());
}

1;

__END__

