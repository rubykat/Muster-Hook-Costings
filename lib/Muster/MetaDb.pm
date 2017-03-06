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

use common::sense;
use DBI;
use Path::Tiny;
use Search::Query;
use Sort::Naturally;
use Text::NeatTemplate;
use YAML::Any;
use POSIX qw(ceil);
use Mojo::URL;

=head1 METHODS

=head2 new

Create a new object, setting global values for the object.

    my $obj = Muster::MetaDb->new(
        metadb_db=>$database);

=cut

sub new {
    my $class = shift;
    my %parameters = (@_);
    my $self = bless ({%parameters}, ref ($class) || $class);

    $self->_set_defaults();

    return ($self);
} # new

=head2 scan_page

Scan one page and add its data to the database

=cut

sub scan_page {
    my $self = shift;
    my $page = shift;

    if (!$self->_connect())
    {
        return undef;
    }

    return $self->_scan_page($page);
} # scan_page

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

    return $self->_process_pagelist(%args);
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

=head2 _set_defaults

Set the defaults for the object if they are not defined already.

=cut
sub _set_defaults {
    my $self = shift;
    my $conf = shift;

    foreach my $key (keys %{$conf})
    {
        if (defined $conf->{$key})
        {
            $self->{$key} = $conf->{$key};
        }
    }

    $self->{metadb_table} = 'pagefields' if !defined $self->{metadb_table};

    if (!defined $self->{metadb_fields})
    {
        # set default fields
        $self->{metadb_fields} = [qw(title pagetitle baseurl parent_page basename description)];
    }
    if (!defined $self->{metadb_db})
    {
        die "No database given";
    }
    $self->{default_limit} = 100 if !defined $self->{default_limit};

    return $self;

} # _set_defaults

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

        # Create the table if it doesn't exist
        my @field_defs = ();
        foreach my $field (@{$self->{metadb_fields}})
        {
            if (exists $self->{metadb_field_types}->{$field})
            {
                push @field_defs, $field . ' ' . $self->{metadb_field_types}->{$field};
            }
            else
            {
                push @field_defs, $field;
            }
        }
        my $table = $self->{metadb_table};
        my $q = "CREATE TABLE IF NOT EXISTS $table (page PRIMARY KEY, "
        . join(", ", @field_defs) .");";
        my $ret = $dbh->do($q);
        if (!$ret)
        {
            $self->{error} = "metadb failed '$q' : $DBI::errstr";
            return 0;
        }
        $self->{dbh} = $dbh;
    }
    else
    {
	$self->{error} = "No Database given." . Dump($self);
        return 0;
    }

    return 1;
} # _connect

=head2 _scan_page

Scan one page and add its data to the database

=cut

sub _scan_page {
    my $self = shift;
    my $page = shift;

} # _scan_page

=head2 _add_meta_to_db

Add a page's metadata to the database.

    $self->_add_meta_to_db($node);

=cut
sub _add_meta_to_db ($$) {
    my $self = shift;
    my $node = shift;

    my $dbh = $self->{dbh};
    if (!$self->{_transaction_on})
    {
	my $ret = $dbh->do("BEGIN TRANSACTION;");
	if (!$ret)
	{
	    $self->{error} = "metadb failed BEGIN TRANSACTION : $DBI::errstr";
            return 0;
	}
	$self->{_transaction_on} = 1;
        $self->{_num_trans} = 0;
    }
    $self->_add_fields($node);
    # do the commits in bursts
    $self->{_num_trans}++;
    if ($self->{_transaction_on} and $self->{_num_trans} > 100)
    {
	my $ret = $dbh->do("COMMIT;");
	if (!$ret)
	{
	    $self->{error} = "metadb failed COMMIT : $DBI::errstr";
            return 0;
	}
	$self->{_transaction_on} = 0;
        $self->{_num_trans} = 0;
    }
} # _add_meta_to_db

=head2 _search

Search the database;
returns the total, the query, and the results for the current page.

$hashref = $dbtable->_search(
q=>$query_string,
tags=>$tags,
p=>$p,
n=>$items_per_page,
sort_by=>$order_by,
);

=cut

sub _search {
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{dbh};

    # first find the total
    my $q = $self->_query_to_sql(%args,get_total=>1);
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
    my @ret_rows=();
    my $total = 0;
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        $total = $row[0];
    }
    my $num_pages = 1;
    if ($args{n})
    {
        $num_pages = ceil($total / $args{n});
        $num_pages = 1 if $num_pages < 1;
    }

    if ($total > 0)
    {
        $q = $self->_query_to_sql(%args,total=>$total);
        $sth = $dbh->prepare($q);
        if (!$sth)
        {
            $self->{error} = "FAILED to prepare '$q' $DBI::errstr";
            return undef;
        }
        $ret = $sth->execute();
        if (!$ret)
        {
            $self->{error} = "FAILED to execute '$q' $DBI::errstr";
            return undef;
        }

        while (my $hashref = $sth->fetchrow_hashref)
        {
            push @ret_rows, $hashref;
        }
    }
    return {rows=>\@ret_rows,
        total=>$total,
        num_pages=>$num_pages,
        sql=>$q};
} # _search

=head2 _process_pagelist

Process the request, return HTML of all the tags.

$dbtable->_process_pagelist(%args);

=cut

sub _process_pagelist {
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{dbh};

} # _process_pagelist

=head2 _page_exists

Does this page exist in the database?

=cut

sub _page_exists {
    my $self = shift;
    my $page = shift;

    my $dbh = $self->{dbh};
    my $table = $self->{metadb_table};

    my $q = "SELECT COUNT(*) FROM $table WHERE page = '$page';";

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
    return $total > 0;
} # _page_exists

=head2 _total_pages

Find the total records in the database.

$dbtable->_total_pages();

=cut

sub _total_pages {
    my $self = shift;

    my $dbh = $self->{dbh};

    my $q = $self->_query_to_sql(get_total=>1);

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

=head2 _build_where

Build (part of) a WHERE condition

$where_cond = $dbtable->build_where(
    q=>$query_string,
    field=>$field_name,
);

=cut

sub _build_where {
    my $self = shift;
    my %args = @_;
    my $field = $args{field};
    my $query_string = $args{q};
    
    # no query, no WHERE
    if (!$query_string)
    {
        return '';
    }

    my $sql_where = '';

    # If there is no field, it is a simple query string;
    # the simple query string will search all columns in OR fashion
    # that is (col1 GLOB term OR col2 GLOB term...) etc
    # only allow for '-' prefix, not the complex Search::Query stuff
    # Note that if this is a NOT term, the query clause needs to be
    # (col1 NOT GLOB term AND col2 NOT GLOB term)
    # and checking for NULL too
    if (!$field)
    {
        my @and_clauses = ();
        my @terms = split(/[ +]/, $query_string);
        for (my $i=0; $i < @terms; $i++)
        {
            my $term = $terms[$i];
            my $not = 0;
            if ($term =~ /^-(.*)/)
            {
                $term = $1;
                $not = 1;
            }
            if ($not) # negative term, match NOT AND
            {
                my @and_not_clauses = ();
                foreach my $col (@{$self->{metadb_fields}})
                {
                    my $clause = sprintf('(%s IS NULL OR %s NOT GLOB "*%s*")', $col, $col, $term);
                    push @and_not_clauses, $clause;
                }
                push @and_clauses, "(" . join(" AND ", @and_not_clauses) . ")";
            }
            else # positive term, match OR
            {
                my @or_clauses = ();
                foreach my $col (@{$self->{metadb_fields}})
                {
                    my $clause = sprintf('%s GLOB "*%s*"', $col, $term);
                    push @or_clauses, $clause;
                }
                push @and_clauses, "(" . join(" OR ", @or_clauses) . ")";
            }
        }
        $sql_where = join(" AND ", @and_clauses);
    }
    elsif ($field eq 'tags'
            or $field eq $self->{tagfield})
    {
        my $tagfield = $self->{tagfield};
        my @and_clauses = ();
        my @terms = split(/[ +]/, $query_string);
        for (my $i=0; $i < @terms; $i++)
        {
            my $term = $terms[$i];
            my $not = 0;
            my $equals = 1; # make tags match exactly by default
            if ($term =~ /^-(.*)/)
            {
                $term = $1;
                $not = 1;
            }
            # use * for a glob marker
            if ($term =~ /^\*(.*)/)
            {
                $term = $1;
                $equals = 0;
            }
            if ($not and !$equals)
            {
                my $clause = sprintf('(%s IS NULL OR %s NOT GLOB "*%s*")', $tagfield, $tagfield, $term);
                push @and_clauses, $clause;
            }
            elsif ($not and $equals) # negative term, match NOT AND
            {
                my $clause = sprintf('(%s IS NULL OR (%s != "%s" AND %s NOT GLOB "%s|*" AND %s NOT GLOB "*|%s|*" AND %s NOT GLOB "*|%s"))',
                    $tagfield,
                    $tagfield, $term,
                    $tagfield, $term,
                    $tagfield, $term,
                    $tagfield, $term,
                );
                push @and_clauses, $clause;
            }
            elsif ($equals) # positive term, match OR
            {
                my $clause = sprintf('(%s = "%s" OR %s GLOB "%s|*" OR %s GLOB "*|%s|*" OR %s GLOB "*|%s")',
                    $tagfield, $term,
                    $tagfield, $term,
                    $tagfield, $term,
                    $tagfield, $term,
                );
                push @and_clauses, $clause;
            }
            else 
            {
                my $clause = sprintf('%s GLOB "*%s*"', $tagfield, $term);
                push @and_clauses, $clause;
            }
        }
        $sql_where = join(" AND ", @and_clauses);
    }
    else # other columns
    {
        my $parser = Search::Query->parser(
            query_class => 'SQL',
            query_class_opts => {
                like => 'GLOB',
                wildcard => '*',
                fuzzify2 => 1,
            },
            null_term => 'NULL',
            default_field => $field,
            default_op => '~',
            fields => [$field],
            );
        my $query  = $parser->parse($args{q});
        $sql_where = $query->stringify;
    }

    return ($sql_where ? "(${sql_where})" : '');
} # _build_where

=head2 _query_to_sql

Convert a query string to an SQL select statement
While this leverages on Select::Query, it does its own thing
for a generic query and for a tags query

$sql = $dbtable->_query_to_sql(
q=>$query_string,
tags=>$tags,
p=>$p,
n=>$items_per_page,
sort_by=>$order_by,
sort_by2=>$order_by2,
sort_by3=>$order_by3,
);

=cut

sub _query_to_sql {
    my $self = shift;
    my %args = @_;

    my $p = $args{p};
    my $items_per_page = $args{n};
    my $total = ($args{total} ? $args{total} : 0);
    my $order_by = '';
    if ($args{sort_by} and $args{sort_by2} and $args{sort_by3})
    {
        $order_by = join(', ', $args{sort_by}, $args{sort_by2}, $args{sort_by3});
    }
    elsif ($args{sort_by} and $args{sort_by2})
    {
        $order_by = join(', ', $args{sort_by}, $args{sort_by2});
    }
    elsif ($args{sort_by})
    {
        $order_by = $args{sort_by};
    }
    else
    {
        $order_by = join(', ', @{$self->{default_sort}});
    }

    my $offset = 0;
    if ($p and $items_per_page)
    {
        $offset = ($p - 1) * $items_per_page;
        if ($total > 0 and $offset >= $total)
        {
            $offset = $total - 1;
        }
        elsif ($offset <= 0)
        {
            $offset = 0;
        }
    }

    my @and_clauses = ();
    foreach my $col (@{$self->{metadb_fields}})
    {
        if ($args{$col})
        {
            my $clause = $self->_build_where(field=>$col, q=>$args{$col});
            push @and_clauses, $clause;
        }
    }
    if ($args{'tags'} and $self->{tagfield} ne 'tags')
    {
        my $clause = $self->_build_where(field=>'tags', q=>$args{'tags'});
        push @and_clauses, $clause;
    }

    if ($args{q})
    {
        my $clause = $self->_build_where(field=>'', q=>$args{q});
        push @and_clauses, $clause;
    }
    # if there's an extra condition in the configuration, add it here
    if ($self->{extra_cond})
    {
        if (@and_clauses)
        {
            push @and_clauses, "(" . $self->{extra_cond} . ")";
        }
        else
        {
            push @and_clauses, $self->{extra_cond};
        }
    }
    my $sql_where = join(" AND ", @and_clauses);

    my $q = '';
    if ($args{get_total})
    {
        $q = "SELECT COUNT(*) FROM " . $self->{metadb_table};
        $q .= " WHERE $sql_where" if $sql_where;
    }
    else
    {
        $q = "SELECT * FROM " . $self->{metadb_table};
        $q .= " WHERE $sql_where" if $sql_where;
        $q .= " ORDER BY $order_by" if $order_by;
        $q .= " LIMIT $items_per_page" if $items_per_page;
        $q .= " OFFSET $offset" if $offset;
    }

    return $q;
} # _query_to_sql

=head2 _add_fields

Add metadata to db.

    $self->_add_fields($node);

=cut
sub _add_fields {
    my $self = shift;
    my $node = shift;
    my $pagename = $node->path();

    my $table = $self->{metadb_table};

    my @values = ();
    foreach my $fn (@{$self->{metadb_fields}})
    {
	my $val = $node->meta($fn);
	if (!defined $val)
	{
	    push @values, "NULL";
	}
	elsif (ref $val)
	{
	    $val = join("|", @{$val});
	    $val =~ s/'/''/g; # sql-friendly quotes
	    push @values, "'$val'";
	}
	else
	{
	    $val =~ s/'/''/g; # sql-friendly quotes
            if ($val =~ /^\d+$/)
            {
	        push @values, $val;
            }
            else
            {
	        push @values, "'$val'";
            }
	}
    }

    # Check if the page exists in the table
    # and do an INSERT or UPDATE depending on whether it does.
    # This is faster than REPLACE because it doesn't need
    # to rebuild indexes.
    my $page_exists = $self->_page_exists($pagename);
    my $iquery;
    if ($page_exists)
    {
	$iquery = "UPDATE $table SET ";
	for (my $i=0; $i < @values; $i++)
	{
	    $iquery .= sprintf('%s = %s', $self->{metadb_fields}->[$i], $values[$i]);
	    if ($i + 1 < @values)
	    {
		$iquery .= ", ";
	    }
	}
	$iquery .= " WHERE page = '$pagename';";
    }
    else
    {
	$iquery = "INSERT INTO $table (page, "
	. join(", ", @{$self->{metadb_fields}}) . ") VALUES ('$pagename', "
	. join(", ", @values) . ");";
    }
    my $ret = $dbh->do($iquery);
    if (!$ret)
    {
	$self->{error} = "metadb failed insert/update '$iquery' : $DBI::errstr";
        return 0;
    }
    return 1;
} # _add_fields

1; # End of Muster::MetaDb
__END__
