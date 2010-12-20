use inc::Module::Install;
use Module::Install::AuthorTests;

name 'PrettyFS';
all_from 'lib/PrettyFS.pm';

requires 'Twiggy';
requires 'Plack' =>  0.9949;
requires 'Config::Tiny';
requires 'Furl' => 0.18;
requires 'Log::Minimal';
requires 'Class::Accessor::Lite' => 0.05;
requires 'Smart::Args';
requires 'Jonk';
requires 'Data::UUID';
requires 'JSON';
requires 'Proc::Guard';
requires 'Sub::Throttle';

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
test_requires 'Test::Requires';
test_requires 'Test::TCP' => 1.10;

author_tests('xt');
WriteAll;
