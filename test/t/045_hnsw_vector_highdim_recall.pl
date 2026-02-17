use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node;
my @queries = ();
my @expected;
my $limit = 10;
my $dim = 1536;
my $count = 1000;
my $array_sql = join(",", ('random()') x $dim);

sub test_recall
{
	my ($min, $operator, $type) = @_;
	my $correct = 0;
	my $total = 0;

	my $explain = $node->safe_psql("postgres", qq(
		SET enable_seqscan = off;
		SET hnsw.ef_search = 200;
		EXPLAIN ANALYZE SELECT i FROM tst ORDER BY v $operator '$queries[0]' LIMIT $limit;
	));
	like($explain, qr/Index Scan/);

	for my $i (0 .. $#queries)
	{
		my $actual = $node->safe_psql("postgres", qq(
			SET enable_seqscan = off;
			SET hnsw.ef_search = 200;
			SELECT i FROM tst ORDER BY v $operator '$queries[$i]' LIMIT $limit;
		));
		my @actual_ids = split("\n", $actual);
		my %actual_set = map { $_ => 1 } @actual_ids;

		my @expected_ids = split("\n", $expected[$i]);

		foreach (@expected_ids)
		{
			if (exists($actual_set{$_}))
			{
				$correct++;
			}
			$total++;
		}
	}

	cmp_ok($correct / $total, ">=", $min, "$type $operator");
}

# Initialize node
$node = PostgreSQL::Test::Cluster->new('node');
$node->init;
$node->start;

# Create table and generate data
$node->safe_psql("postgres", "CREATE EXTENSION vector;");
$node->safe_psql("postgres", "CREATE TABLE tst (i int4, v vector($dim));");
$node->safe_psql("postgres",
	"INSERT INTO tst SELECT i, ARRAY[$array_sql] FROM generate_series(1, $count) i;"
);

# Generate queries
for (1 .. 10)
{
	my @vals = map { rand() } (1 .. $dim);
	my $q = "[" . join(",", @vals) . "]";
	push(@queries, $q);
}

# Test vector with L2, cosine, L1
my @operators = ("<->", "<=>", "<+>");
my @opclasses = ("vector_l2_ops", "vector_cosine_ops", "vector_l1_ops");

for my $i (0 .. $#operators)
{
	my $operator = $operators[$i];
	my $opclass = $opclasses[$i];

	# Get exact results
	@expected = ();
	foreach (@queries)
	{
		my $res = $node->safe_psql("postgres", "SELECT i FROM tst ORDER BY v $operator '$_' LIMIT $limit;");
		push(@expected, $res);
	}

	# Build index with higher ef_construction for high dimensions
	$node->safe_psql("postgres", qq(
		SET max_parallel_maintenance_workers = 0;
		CREATE INDEX idx ON tst USING hnsw (v $opclass) WITH (ef_construction = 128);
	));

	test_recall(0.98, $operator, "vector($dim)");

	$node->safe_psql("postgres", "DROP INDEX idx;");
}

# Clean up vector table
$node->safe_psql("postgres", "DROP TABLE tst;");

# Test halfvec with higher dimensions
my $halfdim = 3072;
my $halfarray_sql = join(",", ('random()') x $halfdim);

$node->safe_psql("postgres", "CREATE TABLE tst (i int4, v halfvec($halfdim));");
$node->safe_psql("postgres",
	"INSERT INTO tst SELECT i, ARRAY[$halfarray_sql]::halfvec($halfdim) FROM generate_series(1, $count) i;"
);

# Generate queries for halfvec
@queries = ();
for (1 .. 10)
{
	my @vals = map { rand() } (1 .. $halfdim);
	my $q = "[" . join(",", @vals) . "]";
	push(@queries, $q);
}

my @half_operators = ("<->", "<=>", "<+>");
my @half_opclasses = ("halfvec_l2_ops", "halfvec_cosine_ops", "halfvec_l1_ops");

for my $i (0 .. $#half_operators)
{
	my $operator = $half_operators[$i];
	my $opclass = $half_opclasses[$i];

	# Get exact results
	@expected = ();
	foreach (@queries)
	{
		my $res = $node->safe_psql("postgres", "SELECT i FROM tst ORDER BY v $operator '$_' LIMIT $limit;");
		push(@expected, $res);
	}

	# Build index with higher ef_construction for high dimensions
	$node->safe_psql("postgres", qq(
		SET max_parallel_maintenance_workers = 0;
		CREATE INDEX idx ON tst USING hnsw (v $opclass) WITH (ef_construction = 128);
	));

	test_recall(0.98, $operator, "halfvec($halfdim)");

	$node->safe_psql("postgres", "DROP INDEX idx;");
}

done_testing();
