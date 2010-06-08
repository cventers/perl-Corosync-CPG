package CorosyncCPGBuilder;

use strict;
use Module::Build;
use vars qw(@ISA);
@ISA = qw(Module::Build);

use File::Temp;
use File::Spec;

sub dist_dir
{
	my $self = shift;
	my $parent_distdir = $self->SUPER::dist_dir;
	return "perl-$parent_distdir";	
}

sub ACTION_rpm
{
	my $self = shift;
	
	# Run the rpmbuild command			
	my $archive = $self->dist_dir() . '.tar.gz';

	# Clean up the old archive if there is one
	unlink($archive);

	# Create the distribution tarball
	$self->depends_on('dist');

	# Build an RPM root
	my $topdir = File::Temp::tempdir(CLEANUP => 1);
	for my $subdir (qw/BUILD RPMS SOURCES SPECS SRPMS/) {
		my $target_dir = File::Spec->catfile($topdir, $subdir);
		mkdir($target_dir) || die $!;
	}	

	# Move tarball into RPM root
	$self->do_system('mv', $archive, "$topdir/SOURCES") || die;

	# Get version and release
	my $version = $self->dist_version;
	my $release = 1;

	# Get install destinations
	$self->installdirs('vendor');
	my @install_dirs = map { ('--define', "_mbdir_$_ " . $self->install_destination($_)) } qw{
		lib arch bin libdoc 
	};

	# Build RPM, SRPM, move out of temporary RPM root
	$self->do_system('rpmbuild', '-ba', '--define', "_topdir $topdir", '--define', "version $version",
					 '--define', "release $release", @install_dirs,
					 'perl-Corosync-CPG.spec') || die;

	# Move packages to package subdirectory
	if (! -d './pkg') {
		mkdir('./pkg') || die $!;
	}
	for my $file (glob("$topdir/RPMS/*/*.rpm"), glob("$topdir/SRPMS/*.rpm")) {
		$self->do_system('mv', '-f', $file, './pkg/') || die;
	}
}

1;
