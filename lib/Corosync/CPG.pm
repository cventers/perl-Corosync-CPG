#!/usr/bin/perl

package Corosync::CPG;

use strict;
use IO::Handle;

require Exporter;
require DynaLoader;

# corosync/corotypes.h / cs_dispatch_flags_t
use constant CS_DISPATCH_ONE            => 1;
use constant CS_DISPATCH_ALL            => 2;
use constant CS_DISPATCH_BLOCKING       => 3;

# corosync/cpg.h / cpg_guarantee_t
use constant CPG_TYPE_UNORDERED         => 0;
use constant CPG_TYPE_FIFO              => 1;
use constant CPG_TYPE_AGREED            => 2;
use constant CPG_TYPE_SAFE              => 3;

# corosync/cpg.h / cpg_flow_control_state_t
use constant CPG_FLOW_CONTROL_DISABLED	=> 0;
use constant CPG_FLOW_CONTROL_ENABLED	=> 1;

# Export constants
my @constants;
push(@constants, qw/
	CS_DISPATCH_ONE
	CS_DISPATCH_ALL
	CS_DISPATCH_BLOCKING

	CPG_TYPE_UNORDERED
	CPG_TYPE_FIFO
	CPG_TYPE_AGREED
	CPG_TYPE_SAFE

	CPG_FLOW_CONTROL_DISABLED
	CPG_FLOW_CONTROL_ENABLED
/);

# Export error constants, but remember their associations so we can
# look up the right name to give with our error messages
my %errmap;
BEGIN {
	my @errs = (
		CS_OK => 1,
		CS_ERR_LIBRARY => 2,
		CS_ERR_VERSION => 3,
		CS_ERR_INIT => 4,
		CS_ERR_TIMEOUT => 5,
		CS_ERR_TRY_AGAIN => 6,
		CS_ERR_INVALID_PARAM => 7,
		CS_ERR_NO_MEMORY => 8,
		CS_ERR_BAD_HANDLE => 9,
		CS_ERR_BUSY => 10,
		CS_ERR_ACCESS => 11,
		CS_ERR_NOT_EXIST => 12,
		CS_ERR_NAME_TOO_LONG => 13,
		CS_ERR_EXIST => 14,
		CS_ERR_NO_SPACE => 15,
		CS_ERR_INTERRUPT => 16,
		CS_ERR_NAME_NOT_FOUND => 17,
		CS_ERR_NO_RESOURCES => 18,
		CS_ERR_NOT_SUPPORTED => 19,
		CS_ERR_BAD_OPERATION => 20,
		CS_ERR_FAILED_OPERATION => 21,
		CS_ERR_MESSAGE_ERROR => 22,
		CS_ERR_QUEUE_FULL => 23,
		CS_ERR_QUEUE_NOT_AVAILABLE => 24,
		CS_ERR_BAD_FLAGS => 25,
		CS_ERR_TOO_BIG => 26,
		CS_ERR_NO_SECTIONS => 27,
		CS_ERR_CONTEXT_NOT_FOUND => 28,
		CS_ERR_TOO_MANY_GROUPS => 30,
		CS_ERR_SECURITY => 100,
	);

	while (1) {
		my $errkey = shift @errs;
		my $errid = shift @errs;
		last unless defined $errkey && defined $errid;

		$errmap{$errid} = $errkey;
		push(@constants, $errkey);

		no strict 'refs';
		*{"$errkey"} = sub { $errid };
	}
}

our @ISA = qw/Exporter DynaLoader/;
our @EXPORT = qw//;
our @EXPORT_OK = @constants;
our %EXPORT_TAGS = ( 'constants' => \@constants );

# Pull in XS code
bootstrap Corosync::CPG;

# Constructs a new instance
sub new {
	my $class = shift;
	my %args = @_;

	my $self = {};

	# Capture callbacks from constructor arguments
	$self->{_cb}{deliver} = delete $args{callbacks}{deliver};
	$self->{_cb}{confchg} = delete $args{callbacks}{confchg};
	$self->{_cb}{error} = delete $args{callbacks}{error};

	# Build the class
	bless($self, $class);

	# Connect to CPG service @ Corosync executive
	my $cpgh = $self->{_cpg_handle} = $self->_initialize;
	defined($cpgh) || $self->_cpgdie;

	$self;
}

# Obtains the current FD as an IO::Handle
sub iohandle_get {
	my $self = shift;
	my $ioh = IO::Handle->new;
	$ioh->fdopen($self->fd_get, 'r') || die $!;
	$ioh;
}

# Obtains the current FD
sub fd_get {
	my $self = shift;
	my $fd = $self->_fd_get();
	defined($fd) || $self->_cpgdie;
	$fd;
}

# Gets the local node ID
sub local_get {
	my $self = shift;
	$self->_local_get;
}

# Joins a cluster group
sub join {
	my $self = shift;
	my $name = shift;

	$self->_join($name) || $self->_cpgdie;
}

# Leaves a cluster group
sub leave {
	my $self = shift;
	my $name = shift;

	$self->_leave($name) || $self->_cpgdie;
}

# Processes data, fires off callbacks
sub dispatch {
	my $self = shift;
	my $type = shift;
	$self->_dispatch($type) || $self->_cpgdie;
}

# Multicasts a message to all the joined cluster group members
sub mcast_joined {
	my $self = shift;
	my $guarantee = shift;

	$self->_mcast_joined($guarantee, @_) || $self->_cpgdie;
}

# Set the deliver callback
sub set_cb_deliver {
	my $self = shift;
	my $cb = shift;

	$self->{_cb}{deliver} = $cb;
}

# Set the configuration change callback
sub set_cb_confchg {
	my $self = shift;
	my $cb = shift;

	$self->{_cb}{confchg} = $cb;
}

# Set the error callback
sub set_cb_error {
	my $self = shift;
	my $cb = shift;

	$self->{_cb}{error} = $cb;
}

# Obtains the current flow control state
sub flow_control_state_get {
	my $self = shift;

	my $fcs = $self->_flow_control_state_get;
	defined($fcs) || $self->_cpgdie;
	return $fcs;
}

# Throws an exception with Corosync error code
sub _cpgdie {
	my $self = shift;
	my $err = $self->{_cs_error};

	if (defined($err)) {
		my $str = $errmap{$err};
		if (defined($str)) {
			$err = "$str ($err)";
		}
	}
	else {
		$err = 'UNKNOWN';
	}

	die "CPG error: $err";
}

# Obtains the membership array for the current group state
sub membership_get {
	my $self = shift;

	my $ret = $self->_membership_get(@_);
	defined($ret) || $self->_cpgdie;
	return $ret;
}

# Callback
sub _cb_deliver {
	my $self = shift;

	if (my $cb = $self->{_cb}{deliver}) {
		&$cb(@_);
	}
}

# Callback
sub _cb_confchg {
	my $self = shift;

	if (my $cb = $self->{_cb}{confchg}) {
		&$cb(@_);
	}
}

# THIS IS WAY YUCKY as it breaks encapsulation. It shall remain undocumented
# in the hopes it can be put out of its misery before it infects anyone.
sub _cb_error {
	my $self = shift;

	if (my $cb = $self->{_cb}{error}) {
		&$cb(@_);
	}
}

1;

__END__

=head1 NAME

Corosync::CPG - Perl bindings for Corosync virtual synchrony / libcpg

=head1 SYNOPSIS

  use Corosync::CPG qw/:constants/;

  # Connect to Corosync executive
  my $cpg = Corosync::CPG->new(
      callbacks => {
          deliver => \&deliver_callback,
          confchg => \&confchg_callback,
      },
  );

  # Join a CPG multicast group
  $cpg->join('TEST_GROUP');

  # Send a CPG message
  $cpg->mcast_joined(CPG_TYPE_AGREED, "the current time is " . time);

  # Non-blocking check for pending messages
  $cpg->dispatch(CS_DISPATCH_ALL);

  # Process pending messages forever
  $cpg->dispatch(CS_DISPATCH_BLOCK);

=head1 DESCRIPTION

Corosync::CPG is a module to enable Perl access to the Corosync CPG service,
courtesy of the system's Corosync executive. CPG enables distributed
applications that operate properly during cluster partitions, merges and
faults. CPG provides reliable, predictably ordered multicast messaging, and
you get notified any time the cluster group gains or loses nodes.

=head1 DEPENDENCIES

=over

=item libcpg.so - Corosync CPG client library

This is the library that talks to the Corosync executive.

=item Running Corosync executive / CPG service

All CPG logic is actually implemented as the CPG service running on the
Corosync executive. Without it, no CPG service is possible.

=item Access to Corosync executive

Accesing the Corosync executive may require your program to be running as the
same username as the executive. Check the Corosync documentation for more
details.

=back

=head1 EVENT PROCESSING

This module exposes the file descriptor being used to communicate with the
Corosync executive via the function call C<fd_get>. To get an C<IO::Handle>
instead of a numeric file descriptor, see C<iohandle_get>. This will allow you
to integrate into other event loops.

Callbacks are executed from the C<dispatch> method.

Note that if you need to associate your own class pointer (or some other data)
with the callbacks you get from a specific instance of the object, but you
don't want the trouble of overloading the class, you can do something like:

  $cpg->set_cb_deliver(sub {
      $self->cpg_deliver_callback(@_);
  });

=over

=item C<_cb_deliver($groupname, $nodeid, $pid, $msg)>

This callback is executed when a new message arrives.

=over

=item C<$groupname>

The group this message came in from.

=item C<$nodeid>

The node id which transmitted the message.

=item C<$pid>

The process ID of the process that transmitted the message.

=item C<$msg>

The raw message we received.

=back

=item C<_cb_confchg($groupname, \@cur_members, \@left_members, \@join_members)>

This callback is executed when the cluster group configuration changes.

=over

=item C<$groupname>

The group experiencing a configuration change.

=item C<\@cur_members>

An array reference to the current membership set (including the described
changes).

=item C<\@left_members>

An array reference to a list of members leaving. Contains an extra key
C<reason> in the member hashes.

=item C<\@join_members>

An array reference to a list of members joining. Contains an extra key
C<reason> in the member hashes.

=back

=back

You can inherit from this module in order to override these methods and catch
these events. Alternatively, you may provide callback subroutine references
to the constructor, or to one of the class's setters.

=head1 METHODS

=head2 C<new(%args)>

Creates a new Corosync::CPG instance, which initiates a connection to the
local Corosync executive.

C<%args> contains:

=over

=item C<callbacks>

=over

=item C<deliver>

A code reference to the C<cb_deliver> callback. See EVENT PROCESSING.

=item C<confchg>

A code reference to the C<cb_confchg> callback. See EVENT PROCESSING.

=back

=back

=head2 C<join($groupname)>

Joins the $groupname cluster group. The string must be non-empty, and must not
exceed 128 bytes.

As per libcpg, each Corosync::CPG instance may only join one cluster group at
a time; however, you may use multiple instances at once.

=head2 C<leave($groupname)>

Leaves the $groupname cluster group.

=head2 C<mcast_joined($type, $msg1, ...)>

Send a multicast message to the joined members of our cluster group.

$type can be one of:

=over

=item CPG_TYPE_AGREED

Reliable message ordering.

=item CPG_TYPE_FIFO

Same as CPG_TYPE_AGREED.

=item CPG_TYPE_SAFE

Messages are delivered in a predictable order and all executives must receive
the message before any deliveries take place. libcpg manpages suggest this is
unimplemented in libcpg.

=item CPG_TYPE_UNORDERED

Messages can be delivered in any arbitrary order. libcpg manpages suggest this
is unimplemented in libcpg.

=back

After $type, the remainder of the arguments are concatenated and transmitted.

=head2 C<fd_get()>

Obtains the numeric file descriptor currently in use to communicate with the
Corosync executive.

=head2 C<iohandle_get()>

Constructs an C<IO::Handle> via C<fdopen> on the fd returned by C<fd_get>.
You can use this to integrate Corosync::CPG with any standard eventloop.

=head2 C<local_get()>

Fetches the local node ID. If you need your own PID, ask Perl for C<$$>.

=head2 C<flow_control_state_get()>

Obtains the current flow control state.

=head2 C<membership_get($groupname)>

Returns an arrayref to the array of current cluster group members. Each
element of the array is a hash with the C<nodeid> and C<pid> keys.

=head2 C<set_cb_deliver($callback)>

Sets the callback for delivery of incoming messages. See the section EVENT
PROCESSING for more information.

=head2 C<set_cb_confchg($callback)>

Sets the callback for delivery of configuration changes (nodes joining or
leaving the cluster group). See the section EVENT PROCESSING for more
information.

=head1 AUTHOR

Chase Venters <chase.venters@gmail.com>

=head1 COPYRIGHT

Copyright (c) 2010 Chase Venters. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms as Perl
itself.

=head1 URL

http://github.com/cventers/perl-Corosync-CPG

