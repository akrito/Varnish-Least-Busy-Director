Summary: Varnish is a high-performance HTTP accelerator
Name: varnish
Version: 1.1.2
Release: 1
License: BSD-like
Group: System Environment/Daemons
URL: http://www.varnish-cache.org/
Source0: http://downloads.sourceforge.net/varnish/varnish-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires: ncurses-devel automake autoconf libtool libxslt
Requires: kernel >= 2.6.0 varnish-libs = %{version}-%{release}
Requires: logrotate
Requires(pre): shadow-utils
Requires(post): /sbin/chkconfig
Requires(preun): /sbin/chkconfig
Requires(preun): /sbin/service

# Varnish actually needs gcc installed to work. It uses the C compiler 
# at runtime to compile the VCL configuration files. This is by design.
Requires: gcc

%description
This is the Varnish high-performance HTTP accelerator. Documentation
wiki and additional information about Varnish is available on the following
web site: http://www.varnish-cache.org/

%package libs
Summary: Libraries for %{name}
Group: System Environment/Libraries
BuildRequires: ncurses-devel
#Requires: ncurses
#Obsoletes: libvarnish1

%description libs
Libraries for %{name}.
Varnish is a high-performance HTTP accelerator.

%package libs-devel
Summary: Development files for %{name}-libs
Group: System Environment/Libraries
BuildRequires: ncurses-devel
Requires: kernel >= 2.6.0 varnish-libs = %{version}-%{release}

%description libs-devel
Development files for %{name}-libs
Varnish is a high-performance HTTP accelerator

%prep
%setup -q

# The svn sources needs to generate a suitable configure script
# Release tarballs would not need this
# ./autogen.sh

%build

# Remove "--disable static" if you want to build static libraries 
%configure --disable-static --localstatedir=/var/lib

# We have to remove rpath - not allowed in Fedora
# (This problem only visible on 64 bit arches)
sed -i 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g;
        s|^runpath_var=LD_RUN_PATH|runpath_var=DIE_RPATH_DIE|g' libtool

%{__make} %{?_smp_mflags}

sed -e ' s/8080/80/g ' etc/default.vcl > redhat/default.vcl


%if "%dist" == "el4"
    sed -i 's,daemon --pidfile \${\?PIDFILE}\?,daemon,g;
            s,status -p \$PIDFILE,status,g;
            s,killproc -p \$PIDFILE,killproc,g' \
    redhat/varnish.initrc redhat/varnishlog.initrc
%endif

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot} INSTALL="install -p"

# None of these for fedora
find %{buildroot}/%{_libdir}/ -name '*.la' -exec rm -f {} ';'

# Remove this line to build a devel package with symlinks
#find %{buildroot}/%{_libdir}/ -name '*.so' -type l -exec rm -f {} ';'

mkdir -p %{buildroot}/var/lib/varnish
mkdir -p %{buildroot}/var/log/varnish

%{__install} -D -m 0644 redhat/default.vcl %{buildroot}%{_sysconfdir}/varnish/default.vcl
%{__install} -D -m 0644 redhat/varnish.sysconfig %{buildroot}%{_sysconfdir}/sysconfig/varnish
%{__install} -D -m 0644 redhat/varnish.logrotate %{buildroot}%{_sysconfdir}/logrotate.d/varnish
%{__install} -D -m 0755 redhat/varnish.initrc %{buildroot}%{_sysconfdir}/init.d/varnish
%{__install} -D -m 0755 redhat/varnishlog.initrc %{buildroot}%{_sysconfdir}/init.d/varnishlog

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_sbindir}/*
%{_bindir}/*
%{_var}/lib/varnish
%{_var}/log/varnish
%{_mandir}/man1/*.1*
%{_mandir}/man7/*.7*
%doc INSTALL LICENSE README redhat/README.redhat redhat/default.vcl ChangeLog 
%dir %{_sysconfdir}/varnish/
%config(noreplace) %{_sysconfdir}/varnish/default.vcl
%config(noreplace) %{_sysconfdir}/sysconfig/varnish
%config(noreplace) %{_sysconfdir}/logrotate.d/varnish
%{_sysconfdir}/init.d/varnish
%{_sysconfdir}/init.d/varnishlog

%files libs
%defattr(-,root,root,-)
%{_libdir}/*.so.*
%doc LICENSE

%files libs-devel
%defattr(-,root,root,-)
%{_libdir}/libvarnish.so
%{_libdir}/libvarnishapi.so
%{_libdir}/libvcl.so
%{_includedir}/varnish/shmlog.h
%{_includedir}/varnish/shmlog_tags.h
%{_includedir}/varnish/stat_field.h
%{_includedir}/varnish/stats.h
%{_includedir}/varnish/varnishapi.h
%{_libdir}/pkgconfig/varnishapi.pc
#%{_libdir}/libvarnish.a
#%{_libdir}/libvarnishapi.a
#%{_libdir}/libvarnishcompat.a
#%{_libdir}/libvcl.a
%doc LICENSE

%pre
getent group varnish >/dev/null || groupadd -r varnish
getent passwd varnish >/dev/null || \
useradd -r -g varnish -d /var/lib/varnish -s /sbin/nologin \
    -c "Varnish http accelerator user" varnish
exit 0

%post
/sbin/chkconfig --add varnish
/sbin/chkconfig --add varnishlog

%preun
if [ $1 -lt 1 ]; then
  /sbin/service varnish stop > /dev/null 2>/dev/null
  /sbin/service varnishlog stop > /dev/null 2>/dev/null
  /sbin/chkconfig --del varnish
  /sbin/chkconfig --del varnishlog
fi

%postun
if [ $1 -ge 1 ]; then
  /sbin/service varnish condrestart > /dev/null 2>/dev/null
  /sbin/service varnishlog condrestart > /dev/null 2>/dev/null
fi

%post libs -p /sbin/ldconfig

%postun libs -p /sbin/ldconfig

%changelog
* Thu Dec 20 2007 Stig Sandbeck Mathisen <ssm@linpro.no> - 1.1.2-1
- Bumped the version number to 1.1.2.
- Addeed build dependency on libxslt

* Mon Aug 20 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.1.1-1
- Bumped the version number to 1.1.1.

* Tue Aug 14 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.1.svn
- Update for 1.1 branch
- Added the devel package for the header files and static library files
- Added a varnish user, and fixed the init script accordingly

* Mon May 28 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.4-3
- Fixed initrc-script bug only visible on el4 (fixes #107)

* Sun May 20 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.4-2
- Repack from unchanged 1.0.4 tarball
- Final review request and CVS request for Fedora Extras
- Repack with extra obsoletes for upgrading from older sf.net package

* Fri May 18 2007 Dag-Erling Smørgrav <des@des.no> - 1.0.4-1
- Bump Version and Release for 1.0.4

* Wed May 16 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.svn-20070517
- Wrapping up for 1.0.4
- Changes in sysconfig and init scripts. Syncing with files in
  trunk/debian

* Fri May 11 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.svn-20070511
- Threw latest changes into svn trunk
- Removed the conversion of manpages into utf8. They are all utf8 in trunk

* Wed May 09 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-7
- Simplified the references to the subpackage names
- Added init and logrotate scripts for varnishlog

* Mon Apr 23 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-6
- Removed unnecessary macro lib_name
- Fixed inconsistently use of brackets in macros
- Added a condrestart to the initscript
- All manfiles included, not just the compressed ones
- Removed explicit requirement for ncurses. rpmbuild figures out the 
  correct deps by itself.
- Added ulimit value to initskript and sysconfig file
- Many thanks to Matthias Saou for valuable input

* Mon Apr 16 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-5
- Added the dist tag
- Exchanged  RPM_BUILD_ROOT variable for buildroot macro
- Removed stripping of binaries to create a meaningful debug package
- Removed BuildRoot and URL from subpackages, they are picked from the
  main package
- Removed duplication of documentation files in the subpackages
- 'chkconfig --list' removed from post script
- Package now includes _sysconfdir/varnish/
- Trimmed package information
- Removed static libs and .so-symlinks. They can be added to a -devel package
  later if anybody misses them

* Wed Feb 28 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-4
- More small specfile fixes for Fedora Extras Package
  Review Request, see bugzilla ticket 230275
- Removed rpath (only visible on x86_64 and probably ppc64)

* Tue Feb 27 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-3
- Made post-1.0.3 changes into a patch to the upstream tarball
- First Fedora Extras Package Review Request

* Fri Feb 23 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-2
- A few other small changes to make rpmlint happy

* Thu Feb 22 2007 Ingvar Hagelund <ingvar@linpro.no> - 1.0.3-1
- New release 1.0.3. See the general ChangeLog
- Splitted the package into varnish, libvarnish1 and
  libvarnish1-devel

* Thu Oct 19 2006 Ingvar Hagelund <ingvar@linpro.no> - 1.0.2-7
- Added a Vendor tag

* Thu Oct 19 2006 Ingvar Hagelund <ingvar@linpro.no> - 1.0.2-6
- Added redhat subdir to svn
- Removed default vcl config file. Used the new upstream variant instead.
- Based build on svn. Running autogen.sh as start of build. Also added
  libtool, autoconf and automake to BuildRequires.
- Removed rule to move varnishd to sbin. This is now fixed in upstream
- Changed the sysconfig script to include a lot more nice features.
  Most of these were ripped from the Debian package. Updated initscript
  to reflect this.

* Tue Oct 10 2006 Ingvar Hagelund <ingvar@linpro.no> - 1.0.1-3
- Moved Red Hat specific files to its own subdirectory

* Tue Sep 26 2006 Ingvar Hagelund <ingvar@linpro.no> - 1.0.1-2
- Added gcc requirement.
- Changed to an even simpler example vcl in to /etc/varnish (thanks, perbu)
- Added a sysconfig entry

* Fri Sep 22 2006 Ingvar Hagelund <ingvar@linpro.no> - 1.0.1-1
- Initial build.
