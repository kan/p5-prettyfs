use inc::Module::Install;
use Module::Install::AuthorTests;

name 'PrettyFS';
all_from 'lib/PrettyFS.pm';

requires 'Twiggy';
requires 'Plack' =>  0.9949;
requires 'Config::Simple';
requires 'Log::Minimal';
requires 'Class::Accessor::Lite' => 0.05;
requires 'Sub::Args';

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';
test_requires 'Test::More' => 0.96; # done_testing, subtest
test_requires 'Test::Requires';
author_tests('xt');
WriteAll;
