package Varnish::API;

use 5.008008;
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Varnish::API ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	VSL_S_BACKEND
	VSL_S_CLIENT
	V_DEAD
	VSL_Arg
	VSL_Dispatch
	VSL_Name
	VSL_New
	VSL_NextLog
	VSL_NonBlocking
	VSL_OpenLog
	VSL_OpenStats
	VSL_Select
	asctime
	asctime_r
	base64_decode
	base64_init
	clock
	clock_getcpuclockid
	clock_getres
	clock_gettime
	clock_nanosleep
	clock_settime
	ctime
	ctime_r
	difftime
	dysize
	getdate
	getdate_r
	gmtime
	gmtime_r
	localtime
	localtime_r
	mktime
	nanosleep
	stime
	strftime
	strftime_l
	strptime
	strptime_l
	time
	timegm
	timelocal
	timer_create
	timer_delete
	timer_getoverrun
	timer_gettime
	timer_settime
	tzset
	varnish_instance
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	VSL_S_BACKEND
	VSL_S_CLIENT
	V_DEAD
);

our $VERSION = '0.01';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Varnish::API::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#XXX	if ($] >= 5.00561) {
#XXX	    *$AUTOLOAD = sub () { $val };
#XXX	}
#XXX	else {
	    *$AUTOLOAD = sub { $val };
#XXX	}
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('Varnish::API', $VERSION);

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Varnish::API - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Varnish::API;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Varnish::API, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.

=head2 Exportable constants

  VSL_S_BACKEND
  VSL_S_CLIENT
  V_DEAD

=head2 Exportable functions

  int VSL_Arg(struct VSL_data *vd, int arg, const char *opt)
  int VSL_Dispatch(struct VSL_data *vd, vsl_handler *func, void *priv)
  const char *VSL_Name(void)
  struct VSL_data *VSL_New(void)
  int VSL_NextLog(struct VSL_data *lh, unsigned char **pp)
  void VSL_NonBlocking(struct VSL_data *vd, int nb)
  int VSL_OpenLog(struct VSL_data *vd, const char *varnish_name)
  struct varnish_stats *VSL_OpenStats(const char *varnish_name)
  void VSL_Select(struct VSL_data *vd, unsigned tag)
  char *asctime (__const struct tm *__tp) __attribute__ ((__nothrow__))
  char *asctime_r (__const struct tm *__restrict __tp,
   char *__restrict __buf) __attribute__ ((__nothrow__))
  int base64_decode(char *d, unsigned dlen, const char *s)
  void base64_init(void)
  clock_t clock (void) __attribute__ ((__nothrow__))
  int clock_getcpuclockid (pid_t __pid, clockid_t *__clock_id) __attribute__ ((__nothrow__))
  int clock_getres (clockid_t __clock_id, struct timespec *__res) __attribute__ ((__nothrow__))
  int clock_gettime (clockid_t __clock_id, struct timespec *__tp) __attribute__ ((__nothrow__))
  int clock_nanosleep (clockid_t __clock_id, int __flags,
       __const struct timespec *__req,
       struct timespec *__rem)
  int clock_settime (clockid_t __clock_id, __const struct timespec *__tp)
     __attribute__ ((__nothrow__))
  char *ctime (__const time_t *__timer) __attribute__ ((__nothrow__))
  char *ctime_r (__const time_t *__restrict __timer,
        char *__restrict __buf) __attribute__ ((__nothrow__))
  double difftime (time_t __time1, time_t __time0)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__))
  int dysize (int __year) __attribute__ ((__nothrow__)) __attribute__ ((__const__))
  struct tm *getdate (__const char *__string)
  int getdate_r (__const char *__restrict __string,
        struct tm *__restrict __resbufp)
  struct tm *gmtime (__const time_t *__timer) __attribute__ ((__nothrow__))
  struct tm *gmtime_r (__const time_t *__restrict __timer,
       struct tm *__restrict __tp) __attribute__ ((__nothrow__))
  struct tm *localtime (__const time_t *__timer) __attribute__ ((__nothrow__))
  struct tm *localtime_r (__const time_t *__restrict __timer,
          struct tm *__restrict __tp) __attribute__ ((__nothrow__))
  time_t mktime (struct tm *__tp) __attribute__ ((__nothrow__))
  int nanosleep (__const struct timespec *__requested_time,
        struct timespec *__remaining)
  int stime (__const time_t *__when) __attribute__ ((__nothrow__))
  size_t strftime (char *__restrict __s, size_t __maxsize,
   __const char *__restrict __format,
   __const struct tm *__restrict __tp) __attribute__ ((__nothrow__))
  size_t strftime_l (char *__restrict __s, size_t __maxsize,
     __const char *__restrict __format,
     __const struct tm *__restrict __tp,
     __locale_t __loc) __attribute__ ((__nothrow__))
  char *strptime (__const char *__restrict __s,
         __const char *__restrict __fmt, struct tm *__tp)
     __attribute__ ((__nothrow__))
  char *strptime_l (__const char *__restrict __s,
    __const char *__restrict __fmt, struct tm *__tp,
    __locale_t __loc) __attribute__ ((__nothrow__))
  time_t time (time_t *__timer) __attribute__ ((__nothrow__))
  time_t timegm (struct tm *__tp) __attribute__ ((__nothrow__))
  time_t timelocal (struct tm *__tp) __attribute__ ((__nothrow__))
  int timer_create (clockid_t __clock_id,
    struct sigevent *__restrict __evp,
    timer_t *__restrict __timerid) __attribute__ ((__nothrow__))
  int timer_delete (timer_t __timerid) __attribute__ ((__nothrow__))
  int timer_getoverrun (timer_t __timerid) __attribute__ ((__nothrow__))
  int timer_gettime (timer_t __timerid, struct itimerspec *__value)
     __attribute__ ((__nothrow__))
  int timer_settime (timer_t __timerid, int __flags,
     __const struct itimerspec *__restrict __value,
     struct itimerspec *__restrict __ovalue) __attribute__ ((__nothrow__))
  void tzset (void) __attribute__ ((__nothrow__))
  int varnish_instance(const char *n_arg, char *name, size_t namelen, char *dir,
    size_t dirlen)



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

A. U. Thor, E<lt>artur@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
