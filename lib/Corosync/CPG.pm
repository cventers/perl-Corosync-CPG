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
my @constants = qw/
	CS_DISPATCH_ONE
	CS_DISPATCH_ALL
	CS_DISPATCH_BLOCKING

	CPG_TYPE_UNORDERED
	CPG_TYPE_FIFO
	CPG_TYPE_AGREED
	CPG_TYPE_SAFE

	CPG_FLOW_CONTROL_DISABLED
	CPG_FLOW_CONTROL_ENABLED
/;

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
    my $err = $self->{_cs_error} || 'UNKNOWN';
    die "CPG error: $err";
}

sub membership_get {
	$_[0]->_membership_get(@_);
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

=item C<_cb_deliver()>

This callback is executed when a new message arrives.

=item C<_cb_confchg()>

This callback is executed when the cluster group configuration changes.

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

=head2 C<membership_get()>

Returns the array of current cluster group members. See the C<_cb_confchg>
callback for details on the format of the hashrefs populating the array.

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

