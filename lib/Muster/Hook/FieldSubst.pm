package Muster::Hook::FieldSubst;

=head1 NAME

Muster::Hook::FieldSubst - Muster hook for field substitution

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::FieldSubst;
  use Mojo::Base 'Muster::Hook';

=head1 DESCRIPTION

L<Muster::Hook::FieldSubst> does field substition;
that is, it replaces a "field macro" with the content of that field
(aka the meta-data for the Leaf).

The pattern for fields is "{{$I<fieldname>}}".

=cut

use Mojo::Base 'Muster::Hook';
use Muster::LeafFile;
use YAML::Any;

=head1 METHODS

=head2 register

Initialize, and register hooks.

=cut
sub register {
    my $self = shift;
    my $hookmaster = shift;
    my $conf = shift;

    # we need to be able to look things up in the database
    $self->{metadb} = $hookmaster->{metadb};

    $hookmaster->add_hook('fieldsubst' => sub {
            my $leaf = shift;
            my $scanning = shift;
            return $self->process($leaf,$scanning);
        },
    );
    return $self;
} # register

=head2 process

Process (scan or modify) a leaf object.
In scanning phase, this will do simple substitutions of known meta-data
(for example, "page").
In assembly phase, it will do the same, but the contents of the Leaf meta-data will likely be more complete.

In either case, this expects the leaf meta-data to be populated.

  my $new_leaf = $self->process($leaf,$scanning);

=cut
sub process {
    my $self = shift;
    my $leaf = shift;
    my $scanning = shift;

    if (!$leaf->pagetype)
    {
        return $leaf;
    }

    my $content = $leaf->cooked();
    my $page = $leaf->pagename;
    ## TODO: Fix destpage for page inclusions
    my $destpage = $page;

    # substitute {{$var}} variables (source-page)
    $content =~ s/(\\?)\{\{\$([-\w]+)\}\}/$self->get_field_value($1,$2,$leaf)/eg;

    # we can't get other pages' meta-data if we are scanning
    # because they haven't been added to the database yet
    if (!$scanning)
    {
        # substitute {{$page#var}} variables (source-page)
        $content =~ s/(\\?)\{\{\$([-\w\/]+)#([-\w]+)\}\}/$self->get_other_page_field_value($1, $3,$leaf,$2)/eg;
    }

    # TODO - deal with destpage/page inclusions

    $leaf->{cooked} = $content;
    return $leaf;
} # process

=head2 get_field_value

Get the field value for this page.

=cut
sub get_field_value {
    my $self = shift;
    my $escape = shift;
    my $field = shift;
    my $leaf = shift;

    if (length $escape)
    {
	return "{{\$${field}}}";
    }
    my $value = '';
    if ($field eq 'page') # page is pagename
    {
        $value = $leaf->pagename;
    }
    elsif (exists $leaf->{meta}->{$field})
    {
        $value = $leaf->{meta}->{$field};
    }
    elsif (exists $leaf->{$field})
    {
        $value = $leaf->{$field};
    }
    if (ref $value eq 'ARRAY')
    {
        $value = join(' ', @{$value});
    }
    elsif (ref $value eq 'HASH')
    {
        $value = Dump($value);
    }
    return $value;
} # get_field_value

=head2 get_other_page_field_value

Get the field value for a different page.

=cut
sub get_other_page_field_value {
    my $self = shift;
    my $escape = shift;
    my $field = shift;
    my $leaf = shift;
    my $other_page = shift;

    if (length $escape)
    {
	return "{{\$${other_page}#${field}}}";
    }
    my $value = '';
    my $use_page = $self->{metadb}->bestlink($leaf->pagename, $other_page);
    # $use_page will be blank if the page doesn't exist
    if ($use_page)
    {
        my $info = $self->{metadb}->page_or_file_info($use_page);
        if ($field eq 'page') # page is pagename
        {
            $value = $info->{pagename};
        }
        elsif (exists $info->{$field})
        {
            $value = $info->{$field};
            if (ref $value eq 'ARRAY')
            {
                $value = join(' ', @{$value});
            }
            elsif (ref $value eq 'HASH')
            {
                $value = Dump($value);
            }
        }
    }

    return $value;
} # get_other_page_field_value

1;
