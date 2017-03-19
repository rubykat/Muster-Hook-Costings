package Muster::Hook::Links;

=head1 NAME

Muster::Hook::Links - Muster hook for links

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::Links;
  use Mojo::Base 'Muster::Hook';

=head1 DESCRIPTION

L<Muster::Hook::Links> processes for links.

=cut

use Mojo::Base 'Muster::Hook';
use Muster::LeafFile;
use File::Basename;
use File::Spec;
use YAML::Any;

# ---------------------------------------------
# Class Variables

# taken from IkiWiki code
my $Link_Regexp = qr{
		\[\[(?=[^!])            # beginning of link
		(?:
			([^\]\|]+)      # 1: link text
			\|              # followed by '|'
		)?                      # optional
		
		([^\n\r\]#]+)           # 2: page to link to
		(?:
			\#              # '#', beginning of anchor
			([^\s\]]+)      # 3: anchor text
		)?                      # optional
		
		\]\]                    # end of link
	}x;

my $Email_Regexp = qr/^.+@.+\..+$/;
my $Url_Regexp = qr/^(?:[^:]+:\/\/|mailto:).*/i;

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

    $hookmaster->add_hook('links' => sub {
            my %args = @_;

            return $self->process(%args);
        },
    );
    return $self;
} # register

=head2 process

Process (scan or modify) a leaf object.
In scanning phase, it may update the meta-data,
in modify phase, it may update the content.
May leave the leaf untouched.

  my $new_leaf = $self->process($leaf,$scanning);

  my $new_leaf = $self->scan($leaf);

=cut
sub process {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $scanning = $args{scanning};

    if (!$leaf->pagetype)
    {
        return $leaf;
    }

    my $content = $leaf->cooked();
    my $page = $leaf->pagename;
    ## TODO: Fix destpage for page inclusions
    my $destpage = $page;

    if ($scanning)
    {
        my %links = ();

        while ($content =~ /(?<!\\)$Link_Regexp/g)
        {
            my $link = $2;
            my $anchor = $3;
            if (! $self->is_externallink($page, $link, $anchor)) {
                $links{$link}++;
            }
        }
        my @links = sort keys %links;
        if (scalar @links)
        {
            $leaf->{meta}->{links} = \@links;
        }
    }
    else
    {
	$content =~ s{(\\?)$Link_Regexp}{
		defined $2
			? ( $1 
				? "[[$2|$3".(defined $4 ? "#$4" : "")."]]" 
				: $self->is_externallink($page, $3, $4)
					? $self->externallink($3, $4, $2)
					: $self->htmllink($page, $destpage, $self->linkpage($3),
						anchor => $4, linktext => $2))
			: ( $1 
				? "[[$3".(defined $4 ? "#$4" : "")."]]"
				: $self->is_externallink($page, $3, $4)
					? $self->externallink($3, $4)
					: $self->htmllink($page, $destpage, $self->linkpage($3),
						anchor => $4))
	}eg;
        $leaf->{cooked} = $content;
    }
    return $leaf;
} # process

=head2 modify

Modifies the "contents" attribute of a leaf object, as part of its processing.

  my $new_leaf = $self->modify($leaf);

=cut
sub modify {
    my $self = shift;
    my $leaf = shift;

    return $leaf;
} # modify

sub is_externallink {
    my $self = shift;
    my $page = shift;
    my $url = shift;
    my $anchor = shift;

    if (defined $anchor) {
        $url.="#".$anchor;
    }

    return ($url =~ /$Url_Regexp|$Email_Regexp/)
}

sub linkpage {
    my $self = shift;
    my $link=shift;
    #my $chars = defined $config{wiki_file_chars} ? $config{wiki_file_chars} : "-[:alnum:]+/.:_";
    my $chars = "-[:alnum:]+/.:_";
    $link=~s/([^$chars])/$1 eq ' ' ? '_' : "__".ord($1)."__"/eg;
    return $link;
}

sub externallink {
    my $self = shift;
    my $url = shift;
    my $anchor = shift;
    my $pagetitle = shift;

    if (defined $anchor) {
        $url.="#".$anchor;
    }

    # build pagetitle
    if (! $pagetitle) {
        $pagetitle = $url;
        # use only the email address as title for mailto: urls
        if ($pagetitle =~ /^mailto:.*/) {
            $pagetitle =~ s/^mailto:([^?]+).*/$1/;
        }
    }

    if ($url !~ /$Url_Regexp/) {
        # handle email addresses (without mailto:)
        $url = "mailto:" . $url;
    }

    return "<a href=\"$url\">$pagetitle</a>";
}

sub htmllink {
    my $self = shift;
    my $lpage=shift; # the page doing the linking
    my $page=shift; # the page that will contain the link (different for inline)
    my $link=shift;
    my %opts=@_;

    $link=~s/\/$//;

    my $bestlink;
    if (! $opts{forcesubpage})
    {
        $bestlink=$self->bestlink(page=>$lpage, link=>$link);
    }
    else
    {
        $bestlink="$lpage/".lc($link);
    }
    # assert: $bestlink contains the page to link to
    my $page_exists = $self->{metadb}->page_exists($bestlink);
    my $bl_info = $page_exists ? $self->{metadb}->page_or_file_info($bestlink) : undef;

    my $linktext;
    if (defined $opts{linktext})
    {
        $linktext=$opts{linktext};
    }
    elsif ($page_exists)
    {
        # use the actual page title
        $linktext=$bl_info->{title};
    }
    else
    {
        $linktext=basename($link);
    }

    return "<span class=\"selflink\">$linktext</span>"
    if length $bestlink && $page eq $bestlink &&
    ! defined $opts{anchor};

    if (!$page_exists or !$bestlink)
    {
        return "<a class=\"createlink\" href=\"$link\">$linktext ?</a>";
    }
    

#    if (! $destsources{$bestlink})
#    {
#        $bestlink=htmlpage($bestlink);
#
#        if (! $destsources{$bestlink})
#        {
#            my $cgilink = "";
#            if (length $config{cgiurl})
#            {
#                $cgilink = "<a href=\"".
#                cgiurl(
#                    do => "create",
#                    page => $link,
#                    from => $lpage
#                )."\" rel=\"nofollow\">?</a>";
#            }
#            return "<span class=\"createlink\">$cgilink$linktext</span>"
#        }
#    }

    $bestlink=File::Spec->abs2rel($bestlink, $page);
    $bestlink=$self->pagelink($bestlink, $bl_info);

    if (defined $opts{anchor}) {
        $bestlink.="#".$opts{anchor};
    }

    my @attrs;
    foreach my $attr (qw{rel class title}) {
        if (defined $opts{$attr}) {
            push @attrs, " $attr=\"$opts{$attr}\"";
        }
    }

    return "<a href=\"$bestlink\"@attrs>$linktext</a>";
}

=head2 bestlink

Figure out the best link from the given page to the given linked page.

=cut
sub bestlink {
    my $self  = shift;
    my %args = @_;

    my $page= $args{page};
    my $link= $args{link};

    return $self->{metadb}->bestlink($page,$link);
} # bestlink

=head2 pagelink

The page as if it were a html link.
This does things like add a trailing slash if it is needed.

=cut
sub pagelink {
    my $self = shift;
    my $link = shift;
    my $info = shift;

    # this is a page, it needs a slash added to it
    if ($info->{pagetype})
    {
        $link .= '/';
    }
    # this is an absolute link, needs a slash in front of it
    if ($link eq $info->{pagename})
    {
        $link = "/$link";
    }
    return $link;
} # pagelink

1;
