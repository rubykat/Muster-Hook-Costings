package Muster::MetaDb;

#ABSTRACT: Muster::MetaDb - keeping meta-data about pages
=head1 NAME

Muster::MetaDb - keeping meta-data about pages

=head1 SYNOPSIS

    use Muster::MetaDb;;

=head1 DESCRIPTION

Content Management System
keeping meta-data about pages.

=cut

use Mojo::Base -base;
use Carp;
use DBI;
use Search::Query;
use Sort::Naturally;
use Text::NeatTemplate;
use YAML::Any;
use POSIX qw(ceil);
use Mojo::URL;

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;

    $self->{primary_fields} = [qw(title name pagetype extension filename parent_page)];
    if (!defined $self->{metadb_db})
    {
        # give a default name
        $self->{metadb_db} = 'muster.sqlite';
    }
    $self->{default_limit} = 100 if !defined $self->{default_limit};

    return $self;

} # init

=head2 update_one_page

Update the meta information for one page

    $self->update_one_page($page, %meta);

=cut

sub update_one_page {
    my $self = shift;
    my $pagename = shift;
    my %args = @_;

    if (!$self->_connect())
    {
        return undef;
    }

    $self->_add_page_data($pagename, %args);

} # update_one_page

=head2 update_all_pages

Update the meta information for all pages.

=cut

sub update_all_pages {
    my $self = shift;
    my %args = @_;

    if (!$self->_connect())
    {
        return undef;
    }

    $self->_update_all_entries(%args);

} # update_all_pages

=head2 delete_one_page

Delete the meta information for one page

    $self->delete_one_page($page);

=cut

sub delete_one_page {
    my $self = shift;
    my $pagename = shift;
    my %args = @_;

    if (!$self->_connect())
    {
        return undef;
    }

    if ($self->_page_exists($pagename))
    {
        return $self->_delete_page_from_db($pagename);
    }

    return 0;
} # delete_one_page

=head2 page_info

Get the info about one page. Returns undef if the page isn't there.

    my $meta = $self->page_info($pagename);

=cut

sub page_info {
    my $self = shift;
    my $pagename = shift;

    if (!$self->_connect())
    {
        return undef;
    }

    return $self->_get_page_meta($pagename);
} # page_info

=head2 pagelist

Query the database, return a list of pages

=cut

sub pagelist {
    my $self = shift;
    my %args = @_;

    if (!$self->_connect())
    {
        return undef;
    }

    return $self->_get_all_pagenames(%args);
} # pagelist

=head2 total_pages

Query the database, return the total number of records.

=cut

sub total_pages {
    my $self = shift;
    my %args = @_;

    if (!$self->_connect())
    {
        return undef;
    }

    return $self->_total_pages(%args);
} # total_pages

=head2 what_error

There was an error, what was it?

=cut

sub what_error {
    my $self = shift;
    my %args = @_;

    return $self->{error};
} # what_error

=head1 Helper Functions

These are functions which are NOT exported by this plugin.

=cut

=head2 _connect

Connect to the database
If we've already connected, do nothing.

=cut

sub _connect {
    my $self = shift;

    my $old_dbh = $self->{dbh};
    if ($old_dbh)
    {
        return 1;
    }

    # The database is expected to be an SQLite file
    # and will be created if it doesn't exist
    my $database = $self->{metadb_db};
    if ($database)
    {
        my $creating_db = 0;
        if (!-r $database)
        {
            $creating_db = 1;
        }
        my $dbh = DBI->connect("dbi:SQLite:dbname=$database", "", "");
        if (!$dbh)
        {
            $self->{error} = "Can't connect to $database $DBI::errstr";
            return 0;
        }
        $dbh->{sqlite_unicode} = 1;
        $self->{dbh} = $dbh;

        # Create the tables if they don't exist
        $self->_create_tables();
    }
    else
    {
	$self->{error} = "No Database given." . Dump($self);
        return 0;
    }

    return 1;
} # _connect

=head2 _create_tables

Create the initial tables in the database:

pages: (page, title, name, pagetype, ext, filename, parent_page)
links: (page, links_to)
attachments: (page, attachment)
deepfields: (page, field, value)

=cut

sub _create_tables {
    my $self = shift;

    return unless $self->{dbh};

    my $dbh = $self->{dbh};

    my $q = "CREATE TABLE IF NOT EXISTS pages (page PRIMARY KEY, " . join(',', @{$self->{primary_fields}}) . ");";
    my $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "CREATE TABLE IF NOT EXISTS links (page, links_to, UNIQUE(page, links_to));";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "CREATE TABLE IF NOT EXISTS attachments (page, attachment, UNIQUE(page, attachment));";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "CREATE TABLE IF NOT EXISTS deepfields (page, field, value, UNIQUE(page, field));";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }

    return 1;
} # _create_tables

=head2 _generate_flatfields_table

Create and populate the flatfields table using the data from the deepfields table.
Expects the deepfields table to be up to date, so this needs to be called
at the end of the scanning pass.

    $self->_generate_flatfields_table();

=cut

sub _generate_flatfields_table {
    my $self = shift;

    return unless $self->{dbh};

    my $dbh = $self->{dbh};

    my @fieldnames = $self->_get_all_fieldnames();

    my $q = "CREATE TABLE IF NOT EXISTS flatfields (page PRIMARY KEY, "
    . join(", ", @fieldnames) .");";
    my $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }

    # prepare the insert query
    my $placeholders = join ", ", ('?') x @fieldnames;
    my $iq = 'INSERT INTO flatfields (page, '
    . join(", ", @fieldnames) . ') VALUES (?, ' . $placeholders . ');';
    my $isth = $dbh->prepare($iq);
    if (!$isth)
    {
        croak __PACKAGE__ . " failed to prepare '$iq' : $DBI::errstr";
    }

    # ---------------------------------------------------
    # Insert values for all the pages
    # ---------------------------------------------------
    my $transaction_on = 0;
    my $num_trans = 0;
    my @pagenames = $self->_get_all_pagenames();
    foreach my $page (@pagenames)
    {
        if (!$transaction_on)
        {
            my $ret = $dbh->do("BEGIN TRANSACTION;");
            if (!$ret)
            {
                croak __PACKAGE__ . " failed 'BEGIN TRANSACTION' : $DBI::errstr";
            }
            $transaction_on = 1;
            $num_trans = 0;
        }
        my $meta = $self->_get_fields_for_page($page);

        my @values = ();
        foreach my $fn (@fieldnames)
        {
            my $val = $meta->{$fn};
            if (!defined $val)
            {
                push @values, undef;
            }
            elsif (ref $val)
            {
                $val = join("|", @{$val});
                push @values, $val;
            }
            else
            {
                push @values, $val;
            }
        }
        # we now have values to insert
        $ret = $isth->execute($page, @values);
        if (!$ret)
        {
            croak __PACKAGE__ . " failed '$iq' (" . join(',', ($page, @values)) . "): $DBI::errstr";
        }
        # do the commits in bursts
        $num_trans++;
        if ($transaction_on and $num_trans > 100)
        {
            $self->_commit();
            $transaction_on = 0;
            $num_trans = 0;
        }

    } # for each page
    $self->_commit();

    return 1;
} # _generate_flatfields_table

=head2 _drop_tables

Drop all the tables in the database.
If one is doing a scan-all-pages pass, dropping and re-creating may be quicker than updating.

=cut

sub _drop_tables {
    my $self = shift;

    return unless $self->{dbh};

    my $dbh = $self->{dbh};

    my $q = "DROP TABLE IF EXISTS pages;";
    my $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "DROP TABLE IF EXISTS links_to;";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "DROP TABLE IF EXISTS attachments;";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "DROP TABLE IF EXISTS deepfields;";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }
    $q = "DROP TABLE IF EXISTS flatfields;";
    $ret = $dbh->do($q);
    if (!$ret)
    {
        croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
    }

    return 1;
} # _drop_tables

=head2 _update_all_entries

Update all pages, adding new ones and deleting non-existent ones.
This expects that the pages passed in are the DEFINITIVE list of pages,
and if a page isn't in this list, it no longer exists.

    $self->_update_all_entries($page=>{...},$page2=>{}...);

=cut
sub _update_all_entries {
    my $self = shift;
    my %pages = @_;

    my $dbh = $self->{dbh};

    # it may save time to drop all the tables and create them again
    $self->_drop_tables();
    $self->_create_tables();

    # update/add pages
    my $transaction_on = 0;
    my $num_trans = 0;
    foreach my $pn (sort keys %pages)
    {
        warn "UPDATING $pn\n";
        if (!$transaction_on)
        {
            my $ret = $dbh->do("BEGIN TRANSACTION;");
            if (!$ret)
            {
                croak __PACKAGE__ . " failed 'BEGIN TRANSACTION' : $DBI::errstr";
            }
            $transaction_on = 1;
            $num_trans = 0;
        }
        $self->_add_page_data($pn, %{$pages{$pn}});
        # do the commits in bursts
        $num_trans++;
        if ($transaction_on and $num_trans > 100)
        {
            $self->_commit();
            $transaction_on = 0;
            $num_trans = 0;
        }
    }
    $self->_commit();
    $self->_generate_flatfields_table();

} # _update_all_entries

=head2 _commit

Commit a pending transaction.

    $self->_commit();

=cut
sub _commit ($%) {
    my $self = shift;
    my %args = @_;
    my $meta = $args{meta};

    return unless $self->{dbh};

    my $ret = $self->{dbh}->do("COMMIT;");
    if (!$ret)
    {
        croak __PACKAGE__ . " failed 'COMMIT' : $DBI::errstr";
    }
} # _commit

=head2 _get_all_pagenames

List of all pagenames

$dbtable->_get_all_pagenames(%args);

=cut

sub _get_all_pagenames {
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{dbh};
    my $q = "SELECT page FROM pages ORDER BY page;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute();
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    my @pagenames = ();
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        push @pagenames, $row[0];
    }

    return @pagenames;
} # _get_all_pagenames

=head2 _get_all_fieldnames

List of the unique field-names from the deepfields table.

    @fieldnames = $self->_get_all_fieldnames();

=cut

sub _get_all_fieldnames {
    my $self = shift;

    my $dbh = $self->{dbh};
    my $q = "SELECT DISTINCT field FROM deepfields ORDER BY field;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute();
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    my @fieldnames = ();
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        push @fieldnames, $row[0];
    }

    return @fieldnames;
} # _get_all_fieldnames

=head2 _get_fields_for_page

Get the field-value pairs for a single page from the deepfields table.

    $meta = $self->_get_fields_for_page($page);

=cut

sub _get_fields_for_page {
    my $self = shift;
    my $pagename = shift;

    return unless $self->{dbh};
    my $dbh = $self->{dbh};
    my $q = "SELECT field, value FROM deepfields WHERE page = ?;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute($pagename);
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    my %meta = ();
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        my $field = $row[0];
        my $value = $row[1];
        $meta{$field} = $value;
    }

    return \%meta;
} # _get_fields_for_page

=head2 _get_page_meta

Get the meta-data for a single page from the flatfields table.

    $meta = $self->_get_page_meta($page);

=cut

sub _get_page_meta {
    my $self = shift;
    my $pagename = shift;

    return unless $self->{dbh};
    my $dbh = $self->{dbh};

    my $q = "SELECT * FROM flatfields WHERE page = ?;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute($pagename);
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    # return the first matching row because there should be only one row
    my $meta;
    if ($meta = $sth->fetchrow_hashref)
    {
        return $meta;
    }

    return undef;
} # _get_page_meta

=head2 _page_exists

Does this page exist in the database?

=cut

sub _page_exists {
    my $self = shift;
    my $page = shift;

    return unless $self->{dbh};
    my $dbh = $self->{dbh};

    my $q = "SELECT COUNT(*) FROM pages WHERE page = ?;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute($page);
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    my $total = 0;
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        $total = $row[0];
    }
    return $total > 0;
} # _page_exists

=head2 _total_pages

Find the total records in the database.

$dbtable->_total_pages();

=cut

sub _total_pages {
    my $self = shift;

    my $dbh = $self->{dbh};

    my $q = "SELECT COUNT(*) FROM pages;";

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
        return undef;
    }
    my $ret = $sth->execute();
    if (!$ret)
    {
        $self->{error} = "FAILED to execute '$q' $DBI::errstr";
        return undef;
    }
    my $total = 0;
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        $total = $row[0];
    }
    return $total;
} # _total_pages

=head2 _add_page_data

Add metadata to db for one page.

    $self->_add_page_data($page, %meta);

=cut
sub _add_page_data {
    my $self = shift;
    my $pagename = shift;
    my %meta = @_;

    return unless $self->{dbh};
    my $dbh = $self->{dbh};

    # ------------------------------------------------
    # TABLE: pages
    # ------------------------------------------------
    my @values = ();
    foreach my $fn (@{$self->{primary_fields}})
    {
	my $val = $meta{$fn};
	if (!defined $val)
	{
	    push @values, undef;
	}
	elsif (ref $val)
	{
	    $val = join("|", @{$val});
	    push @values, $val;
	}
	else
	{
	    push @values, $val;
	}
    }

    # Check if the page exists in the table
    # and do an INSERT or UPDATE depending on whether it does.
    # This is faster than REPLACE because it doesn't need
    # to rebuild indexes.
    my $page_exists = $self->_page_exists($pagename);
    my $q;
    my $ret;
    if ($page_exists)
    {
        $q = "UPDATE pages SET ";
        for (my $i=0; $i < @values; $i++)
        {
            $q .= sprintf('%s = ?', $self->{primary_fields}->[$i]);
            if ($i + 1 < @values)
            {
                $q .= ", ";
            }
        }
        $q .= " WHERE page = '$pagename';";
        my $sth = $dbh->prepare($q);
        if (!$sth)
        {
            croak __PACKAGE__ . " failed to prepare '$q' : $DBI::errstr";
        }
        $ret = $sth->execute(@values);
        if (!$ret)
        {
            croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
        }
    }
    else
    {
        my $placeholders = join ", ", ('?') x @{$self->{primary_fields}};
        $q = 'INSERT INTO pages (page, '
        . join(", ", @{$self->{primary_fields}}) . ') VALUES (?, ' . $placeholders . ');';
        my $sth = $dbh->prepare($q);
        if (!$sth)
        {
            croak __PACKAGE__ . " failed to prepare '$q' : $DBI::errstr";
        }
        $ret = $sth->execute($pagename, @values);
        if (!$ret)
        {
            croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
        }
    }

    # ------------------------------------------------
    # TABLE: links
    # ------------------------------------------------
    if (exists $meta{links} and defined $meta{links})
    {
        my @links = ();
        if (ref $meta{links})
        {
            @links = @{$meta{links}};
        }
        else # one scalar link
        {
            push @links, $meta{links};
        }
        foreach my $link (@links)
        {
            # the "OR IGNORE" allows duplicates to be silently discarded
            $q = "INSERT OR IGNORE INTO links(page, links_to) VALUES('$pagename', '$link');";
            $ret = $dbh->do($q);
            if (!$ret)
            {
                croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
            }
        }
    }
    # ------------------------------------------------
    # TABLE: attachments
    # ------------------------------------------------
    if (exists $meta{attachments} and defined $meta{attachments})
    {
        my @attachments = ();
        if (ref $meta{attachments})
        {
            @attachments = @{$meta{attachments}};
        }
        else # one scalar attachment
        {
            push @attachments, $meta{attachments};
        }
        foreach my $att (@attachments)
        {
            # the "OR IGNORE" allows duplicates to be silently discarded
            $q = "INSERT OR IGNORE INTO attachments(page, attachment) VALUES('$pagename', '$att');";
            $ret = $dbh->do($q);
            if (!$ret)
            {
                croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
            }
        }
    }
    # ------------------------------------------------
    # TABLE: deepfields
    #
    # This is for ALL the meta-data about a page
    # ------------------------------------------------
    foreach my $field (sort keys %meta)
    {
        my $value = $meta{$field};

        next unless defined $value;

        $q = "INSERT OR REPLACE INTO deepfields(page, field, value) VALUES('$pagename', '$field', '$value');";
        $ret = $dbh->do($q);
        if (!$ret)
        {
            croak __PACKAGE__ . " failed '$q' : $DBI::errstr";
        }
    }

    return 1;
} # _add_page_data

sub _delete_page_from_db {
    my $self = shift;
    my $page = shift;

    my $dbh = $self->{dbh};

    foreach my $table (qw(pages links attachments deepfields flatfields))
    {
        my $q = "DELETE FROM $table WHERE page = ?;";
        my $sth = $dbh->prepare($q);
        my $ret = $sth->execute($page);
        if (!$ret)
        {
            croak __PACKAGE__, "FAILED query '$q' $DBI::errstr";
        }
    }

    return 1;
} # _delete_page_from_db

1; # End of Muster::MetaDb
__END__
