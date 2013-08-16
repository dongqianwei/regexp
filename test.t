use v5.16;
use Engine;
use Test::More tests => 4;

my $regexp = 'abc+d?h*ef(xy(zt)*)+g';
my $tsStr = 'abcchhhefxyztztxyg';

ok(match($regexp,$tsStr),'one test');

$regexp = 'abc|def|ghi';
$tsStr = 'abc';
ok(match($regexp,$tsStr),'two test');
$tsStr = 'def';
ok(match($regexp,$tsStr),'three test');
$tsStr = 'ghi';
ok(match($regexp,$tsStr),'four test');
