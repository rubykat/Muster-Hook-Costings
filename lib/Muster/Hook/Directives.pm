package Muster::Hook::Directives;

=head1 NAME

Muster::Hook::Directives - Muster hook for preprocessor directives

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::Directives;
  use Mojo::Base 'Muster::Hook';

=head1 DESCRIPTION

L<Muster::Hook::Directives> processes for preprocessor directives.
This has sub-classes for all the directives.

As with IkiWiki, directives are prefixed with "[[!I<name>"

=cut

use Mojo::Base 'Muster::Hook';
use Carp;
use Muster::LeafFile;
use Muster::Scanner;
use YAML::Any;
use Module::Pluggable search_path => ['Muster::Directive'], instantiate => 'new';


has directives => sub { {} };

=head1 METHODS

=head2 register_scan

Initialize, and register hooks.

=cut
sub register_scan {
    my $self = shift;
    my $scanner = shift;
    my $conf = shift;

    # if there is no config, there are no directives to register
    if (!$conf)
    {
        return $self;
    }
    # Directives are defined by Muster::Directive objects
    # The Pluggable module will find all possible directives
    # but the config will have defined a subset
    my %dirmods = ();
    foreach my $ph ($self->plugins())
    {
        $dirmods{ref $ph} = $ph;
    }
    foreach my $dm (@{$conf->{directives}})
    {
        my $cf = $conf->{direc_conf}->{$dm};
        if ($dirmods{$dm})
        {
            $dirmods{$dm}->register_directive($self,$cf);
        }
        else
        {
            warn "Directive '$dm' does not exist";
        }
    }

    $scanner->add_hook('Directives' => sub {
            my $leaf = shift;
            return $self->scan($leaf);
        },
    );
    return $self;
} # register_scan

=head2 add_directive

Add a scanning hook.

=cut
sub add_directive {
    my ($self, $name, $call) = @_;
    $self->directives->{$name} = $call;
    return $self;
} # add_directive

=head2 register_modify

Initialize, and register hooks.

=cut
sub register_modify {
    my $self = shift;
    my $assembler = shift;
    my $conf = shift;

    # if there is no config, there are no directives to register
    if (!$conf)
    {
        return $self;
    }
    # Directives are defined by Muster::Directive objects
    # The Pluggable module will find all possible directives
    # but the config will have defined a subset
    $self->{directives} = {};
    my %dirmods = ();
    foreach my $ph ($self->plugins())
    {
        $dirmods{ref $ph} = $ph;
        $ph->register_directive($assembler);
    }
    foreach my $dm (@{$conf->{directives}})
    {
        my $cf = $conf->{direc_conf}->{$dm};
        if ($dirmods{$dm})
        {
            $dirmods{$dm}->register_directive($self,$cf);
        }
        else
        {
            warn "Directive '$dm' does not exist";
        }
    }

    $assembler->add_hook('Directives' => sub {
            my $leaf = shift;
            return $self->modify($leaf);
        },
    );
    return $self;
} # register_modify

=head2 scan

Scans a leaf object, updating it with meta-data.
It may also update the "contents" attribute of the leaf object, in order to
prevent earlier-scanned things being re-scanned by something else later in the
scanning pass.
May leave the leaf untouched.

  my $new_leaf = $self->scan($leaf);

=cut
sub scan {
    my $self = shift;
    my $leaf = shift;

    if (!$leaf->pagetype)
    {
        return $leaf;
    }
 
    return $self->do_directives(leaf=>$leaf, scan=>1);
} # scan

=head2 modify

Modifies the "contents" attribute of a leaf object, as part of its processing.

  my $new_leaf = $self->modify($leaf);

=cut
sub modify {
    my $self = shift;
    my $leaf = shift;

    if (!$leaf->pagetype)
    {
        return $leaf;
    }
    return $self->do_directives(leaf=>$leaf, scan=>0);
} # modify

=head2 do_directives

Extracts and processes directives from the content of the leaf.

=cut

sub do_directives {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $scan = $args{scan};
    my $page = $leaf->pagename;
    my $content = $leaf->cooked;

    # adapted fom IkiWiki code
    my $handle=sub {
        my $escape=shift;
        my $prefix=shift;
        my $command=shift;
        my $params=shift;
        $params="" if ! defined $params;

        if (length $escape)
        {
            return "[[$prefix$command $params]]";
        }
        elsif (exists $self->{directives}->{$command})
        {
            # Note: preserve order of params, some plugins may
            # consider it significant.
            my @params;
            while ($params =~ m{
                    (?:([-.\w]+)=)?		# 1: named parameter key?
                    (?:
                        """(.*?)"""	# 2: triple-quoted value
                        |
                        "([^"]*?)"	# 3: single-quoted value
                        |
                        '''(.*?)'''     # 4: triple-single-quote
                        |
                        <<([a-zA-Z]+)\n # 5: heredoc start
                        (.*?)\n\5	# 6: heredoc value
                        |
                        (\S+)		# 7: unquoted value
                    )
                    (?:\s+|$)		# delimiter to next param
                }msgx)
            {
                my $key=$1;
                my $val;
                if (defined $2)
                {
                    $val=$2;
                    $val=~s/\r\n/\n/mg;
                    $val=~s/^\n+//g;
                    $val=~s/\n+$//g;
                }
                elsif (defined $3)
                {
                    $val=$3;
                }
                elsif (defined $4)
                {
                    $val=$4;
                }
                elsif (defined $7)
                {
                    $val=$7;
                }
                elsif (defined $6)
                {
                    $val=$6;
                }

                if (defined $key)
                {
                    push @params, $key, $val;
                }
                else
                {
                    push @params, $val, '';
                }
            }
            if ($self->{preprocessing}->{$page}++ > 8)
            {
                # Avoid loops of preprocessed pages preprocessing
                # other pages that preprocess them, etc.
                return "[[!$command <span class=\"error\">".
                        sprintf("preprocessing loop detected on %s at depth %i",
                            $page, $self->{scanner}->{preprocessing}->{$page}).
                        "</span>]]";
            }
            my $ret;
            if (! $scan) # not scanning
            {
                $ret=eval {
                    $self->{directives}->{$command}($leaf, $scan, @params);
                };
                if ($@)
                {
                    my $error=$@;
                    chomp $error;
                    eval q{use HTML::Entities};
                    $error = encode_entities($error);
                    $ret="[[!$command <span class=\"error\">".
                            "Error".": $error"."</span>]]";
                }
            }
            else # scanning
            {
                eval {
                    $self->{directives}->{$command}($leaf, $scan, @params);
                };
                $ret="";
            }
            $self->{preprocessing}->{$page}--;
            return $ret;
        }
        else # this is not a known command
        {
            return "[[$prefix$command $params]]";
        }
    };

    my $regex = qr{
            (\\?)		# 1: escape?
            \[\[(!)		# directive open; 2: prefix
                    ([-\w]+)	# 3: command
                    (		# 4: the parameters..
                        \s+	# Must have space if parameters present
                        (?:
                            (?:[-.\w]+=)?		# named parameter key?
                            (?:
                                """.*?"""	# triple-quoted value
                                |
                                "[^"]*?"	# single-quoted value
                                |
                                '''.*?'''	# triple-single-quote
                                |
                                <<([a-zA-Z]+)\n # 5: heredoc start
                                (?:.*?)\n\5	# heredoc value
                                |
                                [^"\s\]]+	# unquoted value
                        )
                        \s*			# whitespace or end
                        # of directive
                    )
                    *)?		# 0 or more parameters
                \]\]		# directive closed
    }sx;

    $content =~ s{$regex}{$handle->($1, $2, $3, $4)}eg;

    $leaf->{cooked} = $content;
    return $leaf;
} # do_directives

1;
