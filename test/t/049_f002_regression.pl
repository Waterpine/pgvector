use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('node');
$node->init;
$node->start;
$node->safe_psql('postgres', 'CREATE EXTENSION vector;');
for my $type ('vector', 'halfvec', 'sparsevec')
{
 my ($a,$b,$q) = $type eq 'halfvec' ? ('[29,30]','[22,36]','[7,9]') : ('[5.6480093,1.5518594]','[5.6480103,1.5518594]','[3.2237704,1.7944142]');
 if ($type eq 'sparsevec')
 {
  ($a,$b,$q) = ('{1:5.6480093,2:1.5518594}/2','{1:5.6480103,2:1.5518594}/2','{1:3.2237704,2:1.7944142}/2');
 }
 for my $am ($type eq 'sparsevec' ? ('hnsw') : ('hnsw','ivfflat'))
 {
  my $options = $am eq 'ivfflat' ? 'WITH (lists=1)' : '';
  $node->safe_psql('postgres', qq(
   CREATE TABLE tst (id int, v $type(2), active bool);
   INSERT INTO tst VALUES (1,'$a',true),(2,'$b',true),(3,'$q',false);
   CREATE INDEX tst_idx ON tst USING $am (v ${type}_cosine_ops) $options WHERE active;
  ));
  my $query = "SELECT id FROM tst WHERE active ORDER BY v <=> '$q'::$type";
  my $settings = 'SET enable_seqscan=off; SET enable_sort=off; SET hnsw.ef_search=1000; SET ivfflat.probes=1;';
  like($node->safe_psql('postgres', "$settings EXPLAIN (COSTS OFF) $query"), qr/Index Scan using tst_idx/, "$type $am index used");
  for my $mode ('off','strict_order','relaxed_order')
  {
   is($node->safe_psql('postgres', "$settings SET hnsw.iterative_scan=$mode; $query"), "1\n2", "$type $am $mode SQL distance order");
   is($node->safe_psql('postgres', "$settings SET hnsw.iterative_scan=$mode; $query LIMIT 1"), '1', 'LIMIT follows SQL distance');
  }
  is($node->safe_psql('postgres', qq(
   $settings SET plan_cache_mode=force_generic_plan;
   PREPARE ordered($type) AS SELECT id FROM tst WHERE active ORDER BY v <=> \$1 LIMIT 1;
   EXECUTE ordered('$q'); EXECUTE ordered('$q');
  )), "1\n1", 'generic prepared scan');
  is($node->safe_psql('postgres', qq(
   $settings
   SELECT count(*) FROM (SELECT id FROM tst WHERE active ORDER BY v <=> (SELECT NULL::$type)) s;
  )), '2', 'NULL order argument retains candidates');
  my $zero = $type eq 'sparsevec' ? '{}/2' : '[0,0]';
  is($node->safe_psql('postgres', qq(
   $settings
   SELECT id FROM tst WHERE active
   ORDER BY v <=> '$zero'::$type, v <=> '$q'::$type;
  )), "1\n2", 'multiple cosine order keys, first key NaN');
  $node->safe_psql('postgres', 'DROP TABLE tst;');
 }
}
# The executor rechecks the original index expression, not a normalized key.
$node->safe_psql('postgres', q(
 CREATE TABLE expr (id int, v vector(2));
 INSERT INTO expr VALUES (1,'[29,30]'),(2,'[22,36]');
 CREATE INDEX expr_idx ON expr USING hnsw ((v::halfvec(2)) halfvec_cosine_ops);
));
is($node->safe_psql('postgres', q(
 SET enable_seqscan=off; SET enable_sort=off;
 SELECT id FROM expr ORDER BY v::halfvec(2) <=> '[7,9]'::halfvec;
)), "1\n2", 'expression index rechecks its original expression');
done_testing();
