/*
 * $Id$
 *
 * NB:  This file is machine generated, DO NOT EDIT!
 *
 * Edit vcc_gen_obj.tcl instead
 */

#include <stdio.h>
#include "vcc_compile.h"

struct var vcc_be_vars[] = {
	{ "backend.host", HOSTNAME, 12,
	    NULL,
	    "VRT_l_backend_host(backend, ",
	    V_WO,
	    0,
	    0
	},
	{ "backend.port", PORTNAME, 12,
	    NULL,
	    "VRT_l_backend_port(backend, ",
	    V_WO,
	    0,
	    0
	},
	{ "backend.dnsttl", TIME, 14,
	    NULL,
	    "VRT_l_backend_dnsttl(backend, ",
	    V_WO,
	    0,
	    0
	},
	{ NULL }
};

struct var vcc_vars[] = {
	{ "client.ip", IP, 9,
	    "VRT_r_client_ip(sp)",
	    NULL,
	    V_RO,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DELIVER
	},
	{ "server.ip", IP, 9,
	    "VRT_r_server_ip(sp)",
	    NULL,
	    V_RO,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DELIVER
	},
	{ "req.request", STRING, 11,
	    "VRT_r_req_request(sp)",
	    "VRT_l_req_request(sp, ",
	    V_RW,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "req.url", STRING, 7,
	    "VRT_r_req_url(sp)",
	    "VRT_l_req_url(sp, ",
	    V_RW,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "req.proto", STRING, 9,
	    "VRT_r_req_proto(sp)",
	    "VRT_l_req_proto(sp, ",
	    V_RW,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "req.http.", HEADER, 9,
	    "VRT_r_req_http_(sp)",
	    "VRT_l_req_http_(sp, ",
	    V_RW,
	    "HDR_REQ",
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "req.hash", HASH, 8,
	    NULL,
	    "VRT_l_req_hash(sp, ",
	    V_WO,
	    0,
	    VCL_MET_HASH
	},
	{ "req.backend", BACKEND, 11,
	    "VRT_r_req_backend(sp)",
	    "VRT_l_req_backend(sp, ",
	    V_RW,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "bereq.request", STRING, 13,
	    "VRT_r_bereq_request(sp)",
	    "VRT_l_bereq_request(sp, ",
	    V_RW,
	    0,
	    VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_MISS
	},
	{ "bereq.url", STRING, 9,
	    "VRT_r_bereq_url(sp)",
	    "VRT_l_bereq_url(sp, ",
	    V_RW,
	    0,
	    VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_MISS
	},
	{ "bereq.proto", STRING, 11,
	    "VRT_r_bereq_proto(sp)",
	    "VRT_l_bereq_proto(sp, ",
	    V_RW,
	    0,
	    VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_MISS
	},
	{ "bereq.http.", HEADER, 11,
	    "VRT_r_bereq_http_(sp)",
	    "VRT_l_bereq_http_(sp, ",
	    V_RW,
	    "HDR_BEREQ",
	    VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_MISS
	},
	{ "obj.proto", STRING, 9,
	    "VRT_r_obj_proto(sp)",
	    "VRT_l_obj_proto(sp, ",
	    V_RW,
	    0,
	    VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "obj.status", INT, 10,
	    "VRT_r_obj_status(sp)",
	    "VRT_l_obj_status(sp, ",
	    V_RW,
	    0,
	    VCL_MET_FETCH
	},
	{ "obj.response", STRING, 12,
	    "VRT_r_obj_response(sp)",
	    "VRT_l_obj_response(sp, ",
	    V_RW,
	    0,
	    VCL_MET_FETCH
	},
	{ "obj.http.", HEADER, 9,
	    "VRT_r_obj_http_(sp)",
	    "VRT_l_obj_http_(sp, ",
	    V_RW,
	    "HDR_OBJ",
	    VCL_MET_HIT | VCL_MET_FETCH
	},
	{ "obj.valid", BOOL, 9,
	    "VRT_r_obj_valid(sp)",
	    "VRT_l_obj_valid(sp, ",
	    V_RW,
	    0,
	    VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ "obj.cacheable", BOOL, 13,
	    "VRT_r_obj_cacheable(sp)",
	    "VRT_l_obj_cacheable(sp, ",
	    V_RW,
	    0,
	    VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ "obj.ttl", TIME, 7,
	    "VRT_r_obj_ttl(sp)",
	    "VRT_l_obj_ttl(sp, ",
	    V_RW,
	    0,
	    VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ "obj.lastuse", TIME, 11,
	    "VRT_r_obj_lastuse(sp)",
	    NULL,
	    V_RO,
	    0,
	    VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DELIVER | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ "resp.proto", STRING, 10,
	    "VRT_r_resp_proto(sp)",
	    "VRT_l_resp_proto(sp, ",
	    V_RW,
	    0,
	    VCL_MET_DELIVER
	},
	{ "resp.status", INT, 11,
	    "VRT_r_resp_status(sp)",
	    "VRT_l_resp_status(sp, ",
	    V_RW,
	    0,
	    VCL_MET_DELIVER
	},
	{ "resp.response", STRING, 13,
	    "VRT_r_resp_response(sp)",
	    "VRT_l_resp_response(sp, ",
	    V_RW,
	    0,
	    VCL_MET_DELIVER
	},
	{ "resp.http.", HEADER, 10,
	    "VRT_r_resp_http_(sp)",
	    "VRT_l_resp_http_(sp, ",
	    V_RW,
	    "HDR_RESP",
	    VCL_MET_DELIVER
	},
	{ "now", TIME, 3,
	    "VRT_r_now(sp)",
	    NULL,
	    V_RO,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DELIVER | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ "backend.health", INT, 14,
	    "VRT_r_backend_health(sp)",
	    NULL,
	    V_RO,
	    0,
	    VCL_MET_RECV | VCL_MET_PIPE | VCL_MET_PASS | VCL_MET_HASH | VCL_MET_MISS | VCL_MET_HIT | VCL_MET_FETCH | VCL_MET_DELIVER | VCL_MET_DISCARD | VCL_MET_TIMEOUT
	},
	{ NULL }
};
