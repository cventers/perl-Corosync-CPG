#!/usr/bin/perl

use strict;
use Corosync::CPG qw(:constants);
use Devel::Peek;

my $cpg = Corosync::CPG->new();

$cpg->join('TEST');
my $hostname = `hostname`;
chop $hostname;

while (1) {
	$cpg->mcast_joined(Corosync::CPG::CPG_TYPE_AGREED, "$hostname time is: " . time);
	sleep 1;
	$cpg->dispatch(CS_DISPATCH_ONE);
}

