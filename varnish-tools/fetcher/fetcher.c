/*
 * $Id$
 */

#include <sys/param.h>
#include <sys/socket.h>
#include <sys/time.h>

#include <err.h>
#include <netdb.h>
#include <stdio.h>
#include <fetch.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int verbose;

static char data[8192];

static const char *
read_line(FILE *f)
{
	static char *buf;
	static size_t bufsz;
	const char *line;
	size_t len;

	if ((line = fgetln(f, &len)) == NULL)
		return (NULL);
	while (len && (line[len - 1] == '\r' || line[len - 1] == '\n'))
		--len;
	if (bufsz < len + 1) {
		bufsz = len * 2;
		if ((buf = realloc(buf, bufsz)) == NULL)
			err(1, "realloc()");
	}
	memcpy(buf, line, len);
	buf[len] = '\0';
	if (verbose)
		fprintf(stderr, "<<< [%s]\n", buf);
	return (buf);
}

static int
open_socket(const char *host, const char *port)
{
	struct addrinfo hints, *res;
	int error, sd;

	/* connect to accelerator */
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	if ((error = getaddrinfo(host, port, &hints, &res)) != 0)
		errx(1, "%s", gai_strerror(error));
	if ((sd = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) < 0)
		err(1, "socket()");
	if (connect(sd, res->ai_addr, res->ai_addrlen) < 0)
		err(1, "connect()");
	return (sd);
}

static const char HEAD[] = "HEAD";
static const char GET[] = "GET";

static void
send_request(FILE *f, const char *method, const char *host, const char *url)
{
	static const char *req_pattern =
	    "%s %s HTTP/1.1\r\n"
	    "Host: %s\r\n"
	    "Connection: Keep-Alive\r\n"
	    "\r\n";

	/* send request */
	if (fprintf(f, req_pattern, method, url, host) < 0)
		errx(1, "fprintf()");
	if (verbose)
		fprintf(stderr, req_pattern, method, url, host);
}

static void
receive_response(FILE *f, const char *method)
{
	const char *line;
	size_t clen, rlen;
	int code;

	/* get response header */
	if ((line = read_line(f)) == NULL)
		errx(1, "protocol error");
	if (sscanf(line, "HTTP/%*d.%*d %d %*s", &code) != 1)
		errx(1, "protocol error");
	if (code != 200)
		errx(1, "code %d", code);

	/* get content-length */
	clen = 0;
	for (;;) {
		if ((line = read_line(f)) == NULL)
			errx(1, "protocol error");
		if (line[0] == '\0')
			break;
		sscanf(line, "Content-Length: %zu\n", &clen);
	}

	/* eat contents */
	if (method == HEAD)
		return;
	while (clen > 0) {
		rlen = clen > sizeof(data) ? sizeof(data) : clen;
		clen -= fread(data, 1, rlen, f);
	}
}

static volatile sig_atomic_t got_sig;

static void
handler(int sig)
{
	got_sig = sig;
}

static void
usage(void)
{
	fprintf(stderr, "usage: fetcher [-h]\n");
	exit(1);
}

#define MAX_CTR 5000

int
main(int argc, char *argv[])
{
	struct timeval start, stop;
	double elapsed;
	char url[PATH_MAX];
	int i, opt, sd;
	FILE *f;

	const char *method = GET;
	const char *host = "varnish-test-1.linpro.no";
	const char *url_pattern = "/cgi-bin/recursor.pl?foo=%d";
	int ctr = 500000;

	while ((opt = getopt(argc, argv, "c:hv")) != -1)
		switch (opt) {
		case 'c':
			ctr = atoi(optarg);
			break;
		case 'h':
			method = HEAD;
			break;
		case 'v':
			verbose++;
			break;
		default:
			usage();
		}

	argc -= optind;
	argv += optind;

	if (argc != 0)
		usage();

	sd = open_socket("varnish-test-2.linpro.no", "8080");
	if ((f = fdopen(sd, "w+")) == NULL)
		err(1, "fdopen()");

	got_sig = 0;
	signal(SIGINT, handler);
	signal(SIGTERM, handler);
	gettimeofday(&start, NULL);
	for (i = 0; i < ctr && !got_sig; ++i) {
		snprintf(url, sizeof url, url_pattern, i % MAX_CTR);
		send_request(f, method, host, url);
		receive_response(f, method);
	}
	gettimeofday(&stop, NULL);
	fclose(f);

	elapsed = (stop.tv_sec * 1000000.0 + stop.tv_usec) -
	    (start.tv_sec * 1000000.0 + start.tv_usec);
	fprintf(stderr, "%d requests in %.3f seconds (%d rps)\n",
	    i, elapsed / 1000000, (int)(i / (elapsed / 1000000)));

	exit(got_sig);
}
