#!/usr/bin/perl

use strict;
use Module::Build;
use lib qw(inc);
use CorosyncCPGBuilder;

`./gen-version.sh`;
require './stored-version.pm';
my $distver = join('.', $CorosyncCPGVersion::MAJOR, $CorosyncCPGVersion::MINOR, $CorosyncCPGVersion::EXTRA);

my $build = CorosyncCPGBuilder->new
(
    module_name => 'Corosync::CPG',
    license  => 'perl',
    dist_version => $distver,

    requires => {
        'ExtUtils::CBuilder' => '0',
        'perl'               => '5.6.1',
    },

    xs_files => {
        './CPG.xs' => './Corosync/CPG.xs',
    },

    extra_linker_flags => '-lcpg',
);

$build->create_build_script;

