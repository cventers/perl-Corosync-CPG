#!/usr/bin/perl

use Corosync::CPG;
use Devel::Peek;

my $cpg = Corosync::CPG->new();

$cpg->join('TEST');
my $hostname = `hostname`;
chop $hostname;

while (1) {
        $cpg->mcast_joined(Corosync::CPG::CPG_TYPE_AGREED, "$hostname time is: " . time);

	sleep 1;

	$cpg->dispatch(Corosync::CPG::CS_DISPATCH_ALL);
}

