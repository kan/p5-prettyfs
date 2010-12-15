use strict;
use Test::More;
plan skip_all => "Test::UseAllModules is requires for this method" unless eval "use Test::UseAllModules; 1;";

Test::UseAllModules::all_uses_ok();

