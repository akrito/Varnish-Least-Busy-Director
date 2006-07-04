/*
 * $Id$
 */

#include <sys/param.h>
#include <sys/socket.h>

#include <err.h>
#include <netdb.h>
#include <stdio.h>
#include <fetch.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char HEAD[] = "HEAD";
static const char GET[] = "GET";
static const char *method = GET;
static const char *req_pattern =
"%s /cgi-bin/recursor.pl?foo=%d HTTP/1.1\r\n"
"Host: varnish-test-1.linpro.no\r\n"
"Connection: Keep-Alive\r\n"
"\r\n";

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
#ifdef DEBUG
	fprintf(stderr, "<<< [%s]\n", buf);
#endif
	return (buf);
}

static void
usage(void)
{
	fprintf(stderr, "usage: fetcher [-h]\n");
	exit(1);
}

int
main(int argc, char *argv[])
{
	struct addrinfo hints, *res;
	int clen, code, ctr, error, opt, sd;
	const char *line;
	FILE *f;

	while ((opt = getopt(argc, argv, "h")) != -1)
		switch (opt) {
		case 'h':
			method = HEAD;
			break;
		default:
			usage();
		}

	argc -= optind;
	argv += optind;

	if (argc != 0)
		usage();

	/* connect to accelerator */
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	if ((error = getaddrinfo("varnish-test-2.linpro.no", "http", &hints, &res)) != 0)
		errx(1, "%s", gai_strerror(error));
	if ((sd = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) < 0)
		err(1, "socket()");
	if (connect(sd, res->ai_addr, res->ai_addrlen) < 0)
		err(1, "connect()");
	if ((f = fdopen(sd, "w+")) == NULL)
		err(1, "fdopen()");

	for (ctr = 0; ctr < 5000; ++ctr) {

		/* send request */
		fprintf(f, req_pattern, method, ctr);
#ifdef DEBUG
		fprintf(stderr, req_pattern, method, ctr);
#else
		fprintf(stderr, "\r%d ", ctr);
#endif

		/* get response header */
		if ((line = read_line(f)) == NULL)
			errx(1, "protocol error");
		if (sscanf(line, "HTTP/%*d.%*d %d %*s", &code) != 1)
			errx(1, "protocol error");
		if (code != 200)
			errx(1, "code %d", code);

		/* get content-length */
		clen = -1;
		for (;;) {
			if ((line = read_line(f)) == NULL)
				errx(1, "protocol error");
			if (line[0] == '\0')
				break;
			sscanf(line, "Content-Length: %d\n", &clen);
		}
		if (clen == -1)
			errx(1, "no content length");

		/* eat contents */
		if (method != HEAD)
			while (clen--)
				if (getc(f) == EOF)
					errx(1, "connection prematurely closed");
	}
	fclose(f);

	exit(0);
}
