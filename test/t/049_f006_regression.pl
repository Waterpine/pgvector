use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('node');
$node->init;
$node->start;
$node->safe_psql('postgres', 'CREATE EXTENSION vector;');


my $blocksize = $node->safe_psql('postgres', 'SHOW block_size;');
$node->safe_psql('postgres', 'CREATE TABLE tst (v vector(3));');
# A rejected setting must fail when creating an empty index, before insertion.
for my $m (41, 81, 82, 83, 100)
{
 my ($ret, $out, $err) = $node->psql('postgres', "CREATE INDEX tst_idx ON tst USING hnsw (v vector_l2_ops) WITH (m=$m,ef_construction=200);");
 if ($blocksize == 1024 && $m >= 82)
 {
  isnt($ret, 0, "m=$m rejected on 1 KiB pages");
  like($err, qr/m is too large for this block size/, 'specific parameter error');
 }
 else
 {
  is($ret, 0, "m=$m fits",);
  $node->safe_psql('postgres', "INSERT INTO tst VALUES ('[1,2,3]'); DROP INDEX tst_idx; TRUNCATE tst;");
 }
}
# m=41 previously allowed a level-2 tuple whose alignment overran a 1 KiB page.
$node->safe_psql('postgres', q(
 INSERT INTO tst SELECT ARRAY[i%17,i%23,i%29]::vector FROM generate_series(1,10000)i;
 CREATE INDEX tst_idx ON tst USING hnsw (v vector_l2_ops) WITH (m=41,ef_construction=82);
));
is($node->safe_psql('postgres', q(SET enable_seqscan=off; SELECT count(*) FROM (SELECT v FROM tst ORDER BY v <-> '[1,2,3]' LIMIT 10)q)), '10', 'populated high-level build remains usable');

done_testing();
