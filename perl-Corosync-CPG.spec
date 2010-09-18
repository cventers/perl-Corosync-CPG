Summary:	Perl bindings for libcpg from Corosync
Name:		perl-Corosync-CPG
License:	GPL+ or Artistic
Group:		Development/Libraries
Version:	%{version}
Release:	%{release}
Source0:	perl-Corosync-CPG-%{version}.tar.gz
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:	corosynclib-devel >= 1.2.2
BuildRequires:  perl-Module-Build
Requires:	corosynclib >= 1.2.2
Requires:       perl

%description
This library provides Perl bindings to Corosync from libcpg, so that Perl programs can
access virtual synchrony.

%prep
%setup -q -n perl-Corosync-CPG-%{version}

%build

perl Build.PL --installdirs vendor
./Build

%install

rm -rf %{buildroot}
./Build install --destdir %{buildroot}

%files

%{_mbdir_arch}/Corosync/CPG.pm
%{_mbdir_arch}/auto/Corosync/CPG/.packlist
%{_mbdir_arch}/auto/Corosync/CPG/CPG.bs
%{_mbdir_arch}/auto/Corosync/CPG/CPG.so
%{_mbdir_libdoc}/Corosync::CPG.3pm.gz

%clean
rm -rf %{buildroot}

%changelog
* Fri Sep 18 2010 Chase Venters <chase.venters@gmail.com> 0.0.1-2
- Correct description... evs is a separate service :p

* Tue Jun 08 2010 Chase Venters <chase.venters@gmail.com> 0.0.1-1
- Initial specfile

