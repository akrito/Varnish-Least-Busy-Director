/*-
 * Copyright (c) 2006 Verdens Gang AS
 * Copyright (c) 2006 Linpro AS
 * All rights reserved.
 *
 * Author: Poul-Henning Kamp <phk@phk.freebsd.dk>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $Id$
 *
 * Public definition of the CLI protocol, part of the published Varnish-API.
 *
 * The overall structure of the protocol is a command-line like
 * "command+arguments" request and a IETF style "number + string" response.
 *
 * Arguments can contain arbitrary sequences of bytes which are encoded
 * in back-slash notation in double-quoted, if necessary.
 */

/*
 * These macros define the common data for requests in the CLI protocol.
 * The fields are:
 *	const char *	request_name
 *	const char *	request_syntax (for short help)
 *	const char *	request_help (for long help)
 *	unsigned	minimum_arguments
 *	unsigned	maximum_arguments
 *
 * If you only want a subset of these fields do this:
 *	#define CLIF145(a,b,c,d,e)	a,d,e
 *	[...]
 *	CLIF145(CLI_URL_QUERY)
 *
 */

#define CLI_URL_QUERY							\
	"url.query",							\
	"url.query <url>",						\
	"\tQuery the cache status of a specific URL.\n"			\
	    "\tReturns the TTL, size and checksum of the object.", 	\
	1, 1

#define CLI_URL_PURGE							\
	"url.purge",							\
	"url.purge <regexp>",						\
	"\tAll urls matching regexp will consider currently cached\n"	\
	    "\tobjects obsolete",					\
	1, 1

#define CLI_URL_STATUS							\
	"url.status",							\
	"url.status <url>",						\
	"\tReturns all metadata for the specified URL",			\
	1, 1

#define CLI_VCL_LOAD							\
	"vcl.load",							\
	"vcl.load <configname> <filename>",				\
	"\tCompile and load the VCL file under the name provided.",	\
	2, 2

#define CLI_VCL_INLINE						\
	"vcl.inline",						\
	"vcl.inline <configname> <quoted_VCLstring>",		\
	"\tCompile and load the VCL data under the name provided.",	\
	2, 2

#define CLI_VCL_DISCARD						\
	"vcl.discard",						\
	"vcl.discard <configname>",					\
	"\tUnload the named configuration (when possible).",		\
	1, 1

#define CLI_VCL_LIST							\
	"vcl.list",							\
	"vcl.list",							\
	"\tList all loaded configuration.",				\
	0, 0

#define CLI_VCL_USE							\
	"vcl.use",							\
	"vcl.use <configname>",					\
	"\tSwitch to the named configuration immediately.",		\
	1, 1

#define CLI_PARAM_SHOW							\
	"param.show",							\
	"param.show [-l] [<param>]",					\
	"\tShow parameters and their values.",				\
	0, 2

#define CLI_PARAM_SET							\
	"param.set",							\
	"param.set <param> <value>",					\
	"\tSet parameter value.",					\
	2,2

#define CLI_SERVER_FREEZE						\
	"server.freeze",						\
	"server.freeze",						\
	"\tStop the clock, freeze object store.",			\
	0, 0

#define CLI_SERVER_THAW							\
	"thaw",								\
	"thaw",								\
	"\tRestart the clock, unfreeze object store.",			\
	0, 0

#define CLI_SERVER_SUSPEND						\
	"suspend",							\
	"suspend",							\
	"\tStop accepting requests.",					\
	0, 0

#define CLI_SERVER_RESUME						\
	"resume",							\
	"resume",							\
	"\tAccept requests.",						\
	0, 0

#define CLI_SERVER_STOP							\
	"stop",								\
	"stop",								\
	"\tStop the Varnish cache process",				\
	0, 0

#define CLI_SERVER_START						\
	"start",							\
	"start",							\
	"\tStart the Varnish cache process.",				\
	0, 0

#define CLI_SERVER_RESTART						\
	"restart",							\
	"restart",							\
	"\tRestart the Varnish cache process.",				\
	0, 0

#define CLI_PING							\
	"ping",								\
	"ping [timestamp]",						\
	"\tKeep connection alive",					\
	0, 1

#define CLI_STATS							\
	"stats",							\
	"stats",							\
	"\tShow summary statistics",					\
	0, 0

#define CLI_ZERO							\
	"zero",								\
	"zero",								\
	"\tZero summary statistics",					\
	0, 0

#define CLI_HELP							\
	"help",								\
	"help [command]",						\
	"\tShow command/protocol help",					\
	0, 1

#define CLI_VERBOSE							\
	"verbose",							\
	"verbose",							\
	"\tEnable/Disable verbosity",					\
	0, 0

#define CLI_EXIT							\
	"exit",								\
	"exit",								\
	"\tClose connection",						\
	0, 0

#define CLI_QUIT							\
	"quit",								\
	"quit",								\
	"\tClose connection",						\
	0, 0

#define CLI_BYE								\
	"bye",								\
	"bye",								\
	"\tClose connection",						\
	0, 0

/*
 * Status/return codes in the CLI protocol
 */

enum cli_status_e {
	CLIS_SYNTAX	= 100,
	CLIS_UNKNOWN	= 101,
	CLIS_UNIMPL	= 102,
	CLIS_TOOFEW	= 104,
	CLIS_TOOMANY	= 105,
	CLIS_PARAM	= 106,
	CLIS_OK		= 200,
	CLIS_CANT	= 300,
	CLIS_COMMS	= 400
};

/* Length of first line of response */
#define CLI_LINE0_LEN	13
