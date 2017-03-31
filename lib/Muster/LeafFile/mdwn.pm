package Muster::LeafFile::mdwn;

#ABSTRACT: Muster::LeafFile::mdwn - a Markdown file in a Muster content tree
=head1 NAME

Muster::LeafFile::mdwn - a Markdown file in a Muster content tree

=head1 DESCRIPTION

File nodes represent files in a Muster::Content content tree.
This is a markdown file.

=cut

use Mojo::Base 'Muster::LeafFile';

use Carp;
use Mojo::Util      'decode';
use Text::Markdown::Discount 'markdown';
use Encode qw{encode};
use Hash::Merge;
# use a fast YAML
use YAML::XS;

sub is_this_a_page {
    my $self = shift;

    return 1;
}

sub build_meta {
    my $self = shift;

    my $meta = $self->SUPER::build_meta();

    # add the wordcount to the default meta
    $meta->{wordcount} = $self->wordcount;

    # if there's no YAML in the file then there's no further meta-data
    if (!$self->has_yaml())
    {
        return $meta;
    }

    # We can't just use YAML streams straight, because the second part is
    # generally not YAML-compatible.
    my $yaml_str = $self->get_yaml_part();
    my $ydata;
    eval {$ydata = Load(encode('UTF-8', $yaml_str));};
    if ($@)
    {
        warn __PACKAGE__, " Load of data failed: $@";
        return $meta;
    }
    if (!$ydata)
    {
        warn __PACKAGE__, " no legal YAML";
        return $meta;
    }

    # what is in the YAML overrides the defaults
    my $merge = Hash::Merge->new('RIGHT_PRECEDENT');
    my $new_meta = $merge->merge($meta, $ydata);
    $meta = $new_meta;

    return $meta;
}

# the file has YAML if the FIRST line is '---'
sub has_yaml {
    my $self = shift;

    my $fh;
    if (!open($fh, '<', $self->filename))
    {
        croak __PACKAGE__, " Unable to open file '" . $self->filename ."': $!\n";
    }

    my $first_line = <$fh>;
    close($fh);
    return 0 if !$first_line;

    chomp $first_line;
    return ($first_line eq '---');
}

sub build_raw {
    my $self = shift;

    return $self->get_content_part();
}

# Get the YAML part of a file (if any)
# by reading the stuff between the first set of --- lines
# Don't load the whole file!
# When we want the YAML, we are scanning, and we don't want the content.
sub get_yaml_part {
    my $self = shift;

    my $fh;
    if (!open($fh, '<', $self->filename))
    {
        croak __PACKAGE__, " Unable to open file '" . $self->filename ."': $!\n";
    }

    my $yaml_str = '';
    my $yaml_started = 0;
    while (<$fh>) {
        if (/^---$/) {
            if (!$yaml_started)
            {
                $yaml_started = 1;
                next;
            }
            else # end of the yaml part
            {
                last;
            }
        }
        if ($yaml_started)
        {
            $yaml_str .= $_;
        }
    }
    close($fh);
    return $yaml_str;
}

sub get_content_part {
    my $self = shift;

    my $fh;
    if (!$self->has_yaml())
    {
        # read the whole file
        my $fn = $self->filename;
        open $fh, '<:encoding(UTF-8)', $fn or croak "couldn't open $fn: $!";

        # slurp
        return do { local $/; <$fh> };
    }

    if (!open($fh, '<', $self->filename))
    {
        croak __PACKAGE__, " Unable to open file '" . $self->filename ."': $!\n";
    }

    my $content = '';
    my $yaml_started = 0;
    my $content_started = 0;
    while (<$fh>) {
        if (/^---$/) {
            if (!$yaml_started)
            {
                $yaml_started = 1;
            }
            else # end of the yaml part
            {
                $content_started = 1;
            }
            next;
        }
        if ($content_started)
        {
            $content .= $_;
        }
    }
    close($fh);
    return $content;
}

sub build_html {
    my $self = shift;

    my $content = $self->cooked();
    return markdown($content);
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

