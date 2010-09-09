#!perl -w

use strict;

use Test::More tests => 10;
use Corosync::CPG qw/:constants/;

my $CPG_TESTGRP = 'PERL_COROSYNC_CPG_TEST';
my @events;

# Connect to Corosync executive
my $cpg_handle = Corosync::CPG->new(
	callbacks => {
		confchg => sub {
			push(@events, [ 'confchg', @_ ]);
		},
		deliver => sub {
			push(@events, [ 'deliver', @_ ]);
		},
	},
);
isa_ok($cpg_handle, 'Corosync::CPG');

# Mint an IO::Handle to verify that function
my $iohandle = $cpg_handle->iohandle_get;
isa_ok($iohandle, 'IO::Handle');

# Join test group
$cpg_handle->join($CPG_TESTGRP);
pass("join test group $CPG_TESTGRP");

# Get our Node ID
my $nodeid = $cpg_handle->local_get;
pass("local node is $nodeid, $$");

# Capture our node join event
subtest 'capture join confchg' => sub {
	plan tests => 8;

	$cpg_handle->dispatch(CS_DISPATCH_ALL);
	pass("dispatch callback");

	my $event = shift @events;
	ok(defined($event), "event is defined");

	ok($event->[0] eq 'confchg', "event is confchg event");
	ok($event->[1] eq $CPG_TESTGRP, "confchg event matches test group");

	is_deeply($event->[2], [ { pid => $$, nodeid => $nodeid } ],
		"current members array is correct");

	is_deeply($event->[3], [], "departing members is an empty array");

	is_deeply($event->[4], [ { pid => $$, nodeid => $nodeid, reason => 1 } ],
		"joining members array is correct");

	$event = shift @events;
	ok(!defined($event), "no spurious events");
};

# Verify cluster membership
is_deeply($cpg_handle->membership_get, [
	{ pid => $$, nodeid => $nodeid }
], "cluster membership is correct");

# Send test message
my $testmsg = "testmsg-$$-" . time;
$cpg_handle->mcast_joined(CPG_TYPE_AGREED, $testmsg);
pass("sent multicast message: $testmsg");

# Capture deliver event
subtest 'capture deliver' => sub {
	plan tests => 8;

	$cpg_handle->dispatch(CS_DISPATCH_ALL);
	pass("dispatch callback");

	my $event = shift @events;
	ok(defined($event), "event is defined");

	ok($event->[0] eq 'deliver', "event is deliver event");
	ok($event->[1] eq $CPG_TESTGRP, "deliver event has correct group");
	ok($event->[2] eq $nodeid, "deliver event has correct node id");
	ok($event->[3] eq $$, "deliver event has correct pid");
	ok($event->[4] eq $testmsg, "deliver event has correct message body");
	
	$event = shift @events;
	ok(!defined($event), "no spurious events");
};

# Leave test group
$cpg_handle->leave($CPG_TESTGRP);
pass("leave test group $CPG_TESTGRP");

# Capture our node leave event
subtest 'capture leave confchg' => sub {
	plan tests => 8;

	$cpg_handle->dispatch(CS_DISPATCH_ALL);
	pass("dispatch callback");

	my $event = shift @events;
	ok(defined($event), "event is defined");

	ok($event->[0] eq 'confchg', "event is confchg event");
	ok($event->[1] eq $CPG_TESTGRP, "confchg event matches test group");

	is_deeply($event->[2], [ ],
		"current members array is correct");

	is_deeply($event->[3], [ { pid => $$, nodeid => $nodeid, reason => 2 } ],
		"departing members array is correct");

	is_deeply($event->[4], [], "joining members is an empty array");

	$event = shift @events;
	ok(!defined($event), "no spurious events");
};

