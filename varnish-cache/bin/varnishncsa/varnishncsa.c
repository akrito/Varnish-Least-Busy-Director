/*
 * $Id$
 *
 * Program that will get data from the shared memory log. When it has the data
 * it will order the data based on the sessionid. When the data is ordered
 * and session is finished it will write the data into disk. Logging will be
 * in NCSA extended/combined access log format.
 *
 *	"%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\""
 * 
 * TODO:	- Log in any format one wants
 *		- Maybe rotate/compress log
 */

#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <sbuf.h>
#include <vis.h>

#include "shmlog.h"
#include "varnishapi.h"


/* Ordering-----------------------------------------------------------*/


/* Adding a struct to hold the data for the logline
 *
 */

struct logline {
	char df_h[4 * (3 + 1)]; // Datafield for %h (IP adress)
	//   //   int y;
	//   //   unsigned char *df_l; // Datafield for %l
	//   //   unsigned char *df_u; // Datafield for %u
	//   //   unsigned char *df_t; // Datafield for %t
	//   //   unsigned char *df_r; // Datafield for %r
	//   //   unsigned char *df_s; // Datafield for %s
	//   //   unsigned char *df_b; // Datafield for %b
	//   //   unsigned char *df_R; // Datafield for %{Referer}i
	unsigned char *df_U; // Datafield for %{User-agent}i
};

/* We make a array of pointers to sbuf's. Sbuf is a string buffer.
 * * The buffer can be made/extended/cleared etc. through a API.
 * * The array is 65536 long because we will use sessionid as key.
 * *
 * */

static struct sbuf      *ob[65536];
static struct logline	ll[65536];


/*
* Clean order is called once in a while. It clears all the sessions that 
* where never finished (SLT_SessionClose). Because the data is not complete
* we disregard the data.
*
*/

static void
clean_order(void)
{
	unsigned u;

	for (u = 0; u < 65536; u++) {
		if (ob[u] == NULL)
			continue;
		sbuf_finish(ob[u]);
		sbuf_clear(ob[u]);
	}
}

static void 
extended_log_format(unsigned char *p, char *w_opt)
{
	unsigned u;
	int i,j;
	unsigned char *tmpPtr;
	// Declare the int's that are used to determin if we have all data. 
	int ll_h = 0; // %h
	int ll_U = 0; // %{User-agent}i
	// Declare the data where we store the differnt parts

	if (w_opt != NULL){
		// printf(" Has w_opt\n");
	} else {
		//printf(" Does not have w_opt:\n");
	}

	u = (p[2] << 8) | p[3];
	if (ob[u] == NULL) {
		ob[u] = sbuf_new(NULL, NULL, 0, SBUF_AUTOEXTEND);
		assert(ob[u] != NULL);
	}
	switch (p[0]) {

	case SLT_SessionOpen:
		// Finding the IP adress when data is: "XXX.XXX.XXX.XXX somenumber"

		tmpPtr = strchr(p + 4, ' ');
	        j = strlen(p + 4) - strlen(tmpPtr);                // length of IP
	        strncpy(ll[u].df_h, p + 4, j);
		ll[u].df_h[j] = '\0'; // put on a NULL at end of buffer.

		break;

	case SLT_RxHeader:
			
		if (p[1] >= 11 && !strncasecmp((void *)&p[4], "user-agent:",11)){
			ll[u].df_U = strdup(p + 4);
		}

		break;

	case SLT_StatAddr:

		break;
	
	case SLT_SessionClose:
		printf("Closing session [%d]: %s %s\n",u, ll[u].df_h, ll[u].df_U);
		break;
	default:
		break;
	}

	

	if (0) {
		
	}
	
	
}

/*--------------------------------------------------------------------*/

static void
Usage(void)
{
	fprintf(stderr, "Usage: varnishlogfile [-w file] [-r file]\n");
	exit(2);
}

int
main(int argc, char **argv)
{
	int i, c;
	unsigned u, v;
	unsigned char *p;
	char *w_opt = NULL;
	FILE *wfile = NULL;
	struct VSL_data *vd;

	vd = VSL_New();
	
	while ((c = getopt(argc, argv, VSL_ARGS "w:")) != -1) {
		i = VSL_Arg(vd, c, optarg);
		if (i < 0)
			exit (1);
		if (i > 0)
			continue;
		switch (c) {
		case 'w':
			w_opt = optarg;
			break;
		default:
			Usage();
		}
	}

	if (VSL_OpenLog(vd))
		exit (1);

	if (w_opt != NULL) {
		wfile = fopen(w_opt, "w");
		if (wfile == NULL) {
			perror(w_opt);
			exit (1);
		}
	}
	u = 0;
	v = 0;

	while (1) {
		i = VSL_NextLog(vd, &p);
		if (i < 0)
			break;
		if (i == 0) {
			if (w_opt == NULL) {
				if (++v == 100){
					clean_order();
					fflush(stdout);
				}
			} 
			usleep(50000);
			continue;
		}
		v = 0;
		
		extended_log_format(p, w_opt);
	}
	
	clean_order();
	return (0);
}

