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

static int random_order;
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

static int reqcount;

static void
send_request(FILE *f, const char *method, const char *host, const char *url)
{
	static const char *req_pattern =
	    "%s %s HTTP/1.1\r\n"
	    "Host: %s\r\n"
	    "Connection: Keep-Alive\r\n"
	    "\r\n";

	reqcount++;

	/* send request */
	if (fprintf(f, req_pattern, method, url, host) < 0)
		errx(1, "fprintf()");
	if (verbose)
		fprintf(stderr, req_pattern, method, url, host);
}

static int respcount;

static void
receive_response(FILE *f, const char *method)
{
	const char *line;
	size_t clen, rlen;
	int code;

	respcount++;

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
		rlen = fread(data, 1, rlen, f);
		if (rlen == 0)
			err(1, "fread()");
		if (verbose)
			fprintf(stderr, "read %zu bytes\n", rlen);
		clen -= rlen;
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

#define MAX_CTR 100000

int
main(int argc, char *argv[])
{
	struct timeval start, stop;
	double elapsed;
	char url[PATH_MAX];
	int opt, sd;
	FILE *f;

	const char *method = GET;
	const char *host = "varnish-test-1.linpro.no";
	const char *url_pattern = "/cgi-bin/recursor.pl?foo=%d";
	int ctr = MAX_CTR * 10;
	int depth = 1;

	while ((opt = getopt(argc, argv, "c:d:hrv")) != -1)
		switch (opt) {
		case 'c':
			ctr = atoi(optarg);
			break;
		case 'd':
			depth = atoi(optarg);
			break;
		case 'h':
			method = HEAD;
			break;
		case 'r':
			random_order++;
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

	if (random_order)
		srandomdev();

	sd = open_socket("varnish-test-2.linpro.no", "8080");
	if ((f = fdopen(sd, "w+")) == NULL)
		err(1, "fdopen()");

	got_sig = 0;
	signal(SIGINT, handler);
	signal(SIGTERM, handler);
	gettimeofday(&start, NULL);
	while (respcount < ctr && !got_sig) {
		while (reqcount < ctr && reqcount - respcount < depth && !got_sig) {
			int serial = (random_order ? random() : reqcount) % MAX_CTR;
			if (!verbose && (random_order || (reqcount % 29) == 0))
				fprintf(stderr, "\r%d ", serial);
			snprintf(url, sizeof url, url_pattern, serial);
			send_request(f, method, host, url);
		}
		receive_response(f, method);
	}
	gettimeofday(&stop, NULL);
	fclose(f);

	elapsed = (stop.tv_sec * 1000000.0 + stop.tv_usec) -
	    (start.tv_sec * 1000000.0 + start.tv_usec);
	fprintf(stderr, "%d requests in %.3f seconds (%d rps)\n",
	    reqcount, elapsed / 1000000, (int)(reqcount / (elapsed / 1000000)));

	exit(got_sig);
}
