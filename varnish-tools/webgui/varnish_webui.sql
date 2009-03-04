-- This file was auto generated Mon Feb 23 08:16:23 2009 by create_db_files.pl
DROP TABLE node_group;
DROP TABLE node;
DROP TABLE stat;
DROP TABLE parameters;
DROP TABLE parameter_info;
DROP TABLE vcl;

CREATE TABLE node_group (
	id INTEGER PRIMARY KEY,
	active_vcl TEXT,
	name text
);

CREATE TABLE node (
	id INTEGER PRIMARY KEY,
	name TEXT,
	address TEXT,
	port TEXT,
	group_id INTEGER,
	management_port TEXT,
	management_secret TEXT
);

CREATE TABLE stat (
	id INTEGER PRIMARY KEY,
	time TIMESTAMP,
	node_id INTEGER,
session_pipeline INTEGER,
shm_mtx_contention INTEGER,
n_overflowed_work_requests INTEGER,
backend_connections_failures INTEGER,
n_worker_threads_limited INTEGER,
sma_outstanding_bytes INTEGER,
backend_connections_too_many INTEGER,
shm_cycles_through_buffer INTEGER,
esi_parse_errors__unlock_ INTEGER,
total_pipe INTEGER,
n_worker_threads_created INTEGER,
objects_sent_with_write INTEGER,
backend_connections_success INTEGER,
n_dropped_work_requests INTEGER,
objects_overflowing_workspace INTEGER,
sms_outstanding_bytes INTEGER,
client_requests_received INTEGER,
n_objects_on_deathrow INTEGER,
n_total_active_purges INTEGER,
backend_requests_made INTEGER,
bytes_allocated INTEGER,
outstanding_allocations INTEGER,
objects_esi_parsed__unlock_ INTEGER,
n_struct_vbe_conn INTEGER,
cache_hits_for_pass INTEGER,
n_lru_saved_objects INTEGER,
cache_hits INTEGER,
sma_outstanding_allocations INTEGER,
total_pass INTEGER,
backend_connections_reuses INTEGER,
backend_connections_not_attempted INTEGER,
shm_flushes_due_to_overflow INTEGER,
n_duplicate_purges_removed INTEGER,
n_new_purges_added INTEGER,
session_closed INTEGER,
cache_misses INTEGER,
n_struct_srcaddr INTEGER,
sms_allocator_requests INTEGER,
session_herd INTEGER,
n_worker_threads_not_created INTEGER,
n_vcl_discarded INTEGER,
hcb_lookups_without_lock INTEGER,
n_worker_threads INTEGER,
n_lru_nuked_objects INTEGER,
n_queued_work_requests INTEGER,
total_sessions INTEGER,
total_header_bytes INTEGER,
n_objects_tested INTEGER,
n_active_struct_srcaddr INTEGER,
bytes_free INTEGER,
n_vcl_total INTEGER,
n_backends INTEGER,
sma_bytes_free INTEGER,
total_body_bytes INTEGER,
shm_records INTEGER,
n_vcl_available INTEGER,
sma_bytes_allocated INTEGER,
objects_sent_with_sendfile INTEGER,
hcb_lookups_with_lock INTEGER,
n_struct_sess_mem INTEGER,
client_connections_accepted INTEGER,
n_struct_bereq INTEGER,
sms_bytes_freed INTEGER,
sms_outstanding_allocations INTEGER,
sms_bytes_allocated INTEGER,
n_small_free_smf INTEGER,
n_struct_objecthead INTEGER,
total_fetch INTEGER,
sma_allocator_requests INTEGER,
backend_connections_recycles INTEGER,
backend_connections_unused INTEGER,
shm_writes INTEGER,
n_struct_object INTEGER,
total_requests INTEGER,
hcb_inserts INTEGER,
n_lru_moved_objects INTEGER,
n_struct_sess INTEGER,
allocator_requests INTEGER,
n_regexps_tested_against INTEGER,
n_expired_objects INTEGER,
http_header_overflows INTEGER,
n_struct_smf INTEGER,
n_old_purges_deleted INTEGER,
n_large_free_smf INTEGER,
session_read_ahead INTEGER,
session_linger INTEGER,

	has_data INTEGER
);

CREATE TABLE parameters (
	id INTEGER PRIMARY KEY,
accept_fd_holdoff TEXT,
auto_restart TEXT,
backend_http11 TEXT,
between_bytes_timeout TEXT,
cache_vbe_conns TEXT,
cc_command TEXT,
cli_banner TEXT,
cli_buffer TEXT,
cli_timeout TEXT,
client_http11 TEXT,
clock_skew TEXT,
connect_timeout TEXT,
default_grace TEXT,
default_ttl TEXT,
diag_bitmap TEXT,
err_ttl TEXT,
esi_syntax TEXT,
fetch_chunksize TEXT,
first_byte_timeout TEXT,
child_group TEXT,
listen_address TEXT,
listen_depth TEXT,
log_hashstring TEXT,
log_local_address TEXT,
lru_interval TEXT,
max_esi_includes TEXT,
max_restarts TEXT,
obj_workspace TEXT,
overflow_max TEXT,
ping_interval TEXT,
pipe_timeout TEXT,
prefer_ipv6 TEXT,
purge_dups TEXT,
purge_hash TEXT,
rush_exponent TEXT,
send_timeout TEXT,
sess_timeout TEXT,
sess_workspace TEXT,
session_linger TEXT,
shm_reclen TEXT,
shm_workspace TEXT,
srcaddr_hash TEXT,
srcaddr_ttl TEXT,
thread_pool_add_delay TEXT,
thread_pool_add_threshold TEXT,
thread_pool_fail_delay TEXT,
thread_pool_max TEXT,
thread_pool_min TEXT,
thread_pool_purge_delay TEXT,
thread_pool_timeout TEXT,
thread_pools TEXT,
child_user TEXT,
vcl_trace TEXT,
waiter TEXT,

	group_id INTEGER
);

CREATE TABLE vcl(
	group_id INTEGER,
	name TEXT,
	vcl TEXT
);

CREATE TABLE parameter_info(
	name TEXT PRIMARY KEY,
	unit TEXT,
	description TEXT
);

CREATE INDEX stat_time ON stat(time);
CREATE INDEX stat_node_id ON stat(node_id);

INSERT INTO node_group VALUES(0, 0, 'Standalone');

INSERT INTO parameter_info VALUES('accept_fd_holdoff', 'ms', 'Default is 50. If we run out of file descriptors, the accept thread will sleep.  This parameter control for how long it will sleep.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('auto_restart', 'bool', 'Default is on. Restart child process automatically if it dies. ');
INSERT INTO parameter_info VALUES('backend_http11', 'bool', 'Default is on. Force all backend requests to be HTTP/1.1. By default we copy the protocol version from the incoming client request.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('between_bytes_timeout', 's', 'Default is 60. Default timeout between bytes when receiving data from backend. We only wait for this many seconds between bytes before giving up. A value of 0 means it will never time out. VCL can override this default value for each backend request and backend request. This parameter does not apply to pipe. ');
INSERT INTO parameter_info VALUES('cache_vbe_conns', 'bool', 'Default is off. Cache vbe_conn''s or rely on malloc, that''s the question.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('cc_command', '', 'Default is exec cc -fpic -shared -Wl,-x -o %o %s. Command used for compiling the C source code to a dlopen(3) loadable object.  Any occurrence of %s in the string will be replaced with the source file name, and %o will be replaced with the output file name.   NB: This parameter will not take any effect until the VCL programs have been reloaded. ');
INSERT INTO parameter_info VALUES('cli_banner', 'bool', 'Default is on. Emit CLI banner on connect. Set to off for compatibility with pre 2.1 versions. ');
INSERT INTO parameter_info VALUES('cli_buffer', 'bytes', 'Default is 8192. Size of buffer for CLI input. You may need to increase this if you have big VCL files and use the vcl.inline CLI command. NB: Must be specified with -p to have effect. ');
INSERT INTO parameter_info VALUES('cli_timeout', 'seconds', 'Default is 5. Timeout for the childs replies to CLI requests from the master. ');
INSERT INTO parameter_info VALUES('client_http11', 'bool', 'Default is off. Force all client responses to be HTTP/1.1. By default we copy the protocol version from the backend response.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('clock_skew', 's', 'Default is 10. How much clockskew we are willing to accept between the backend and our own clock. ');
INSERT INTO parameter_info VALUES('connect_timeout', 's', 'Default is 0.4. Default connection timeout for backend connections. We only try to connect to the backend for this many seconds before giving up. VCL can override this default value for each backend and backend request. ');
INSERT INTO parameter_info VALUES('default_grace', '', 'Default is 10seconds. Default grace period.  We will deliver an object this long after it has expired, provided another thread is attempting to get a new copy.   NB: This parameter may take quite some time to take (full) effect. ');
INSERT INTO parameter_info VALUES('default_ttl', 'seconds', 'Default is 120. The TTL assigned to objects if neither the backend nor the VCL code assigns one. Objects already cached will not be affected by changes made until they are fetched from the backend again. To force an immediate effect at the expense of a total flush of the cache use "url.purge ." ');
INSERT INTO parameter_info VALUES('diag_bitmap', 'bitmap', 'Default is 0. Bitmap controlling diagnostics code: 0x00000001 - CNT_Session states. 0x00000002 - workspace debugging. 0x00000004 - kqueue debugging. 0x00000008 - mutex logging. 0x00000010 - mutex contests. 0x00000020 - waiting list. 0x00000040 - object workspace. 0x00001000 - do not core-dump child process. 0x00002000 - only short panic message. 0x00004000 - panic to stderr. 0x00010000 - synchronize shmlog. Use 0x notation and do the bitor in your head :-) ');
INSERT INTO parameter_info VALUES('err_ttl', 'seconds', 'Default is 0. The TTL assigned to the synthesized error pages ');
INSERT INTO parameter_info VALUES('esi_syntax', 'bitmap', 'Default is 0. Bitmap controlling ESI parsing code: 0x00000001 - Don''t check if it looks like XML 0x00000002 - Ignore non-esi elements 0x00000004 - Emit parsing debug records Use 0x notation and do the bitor in your head :-) ');
INSERT INTO parameter_info VALUES('fetch_chunksize', 'kilobytes', 'Default is 128. The default chunksize used by fetcher. This should be bigger than the majority of objects with short TTLs. Internal limits in the storage_file module makes increases above 128kb a dubious idea.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('first_byte_timeout', 's', 'Default is 60. Default timeout for receiving first byte from backend. We only wait for this many seconds for the first byte before giving up. A value of 0 means it will never time out. VCL can override this default value for each backend and backend request. This parameter does not apply to pipe. ');
INSERT INTO parameter_info VALUES('child_group', '', 'Default is . The unprivileged group to run as.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('listen_address', '', 'Default is :80. Whitespace separated list of network endpoints where Varnish will accept requests. Possible formats: host, host:port, :port   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('listen_depth', 'connections', 'Default is 1024. Listen queue depth.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('log_hashstring', 'bool', 'Default is off. Log the hash string to shared memory log. ');
INSERT INTO parameter_info VALUES('log_local_address', 'bool', 'Default is off. Log the local address on the TCP connection in the SessionOpen shared memory record. ');
INSERT INTO parameter_info VALUES('lru_interval', 'seconds', 'Default is 2. Grace period before object moves on LRU list. Objects are only moved to the front of the LRU list if they have not been moved there already inside this timeout period.  This reduces the amount of lock operations necessary for LRU list access.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('max_esi_includes', 'includes', 'Default is 5. Maximum depth of esi:include processing. ');
INSERT INTO parameter_info VALUES('max_restarts', 'restarts', 'Default is 4. Upper limit on how many times a request can restart. Be aware that restarts are likely to cause a hit against the backend, so don''t increase thoughtlessly. ');
INSERT INTO parameter_info VALUES('obj_workspace', 'bytes', 'Default is 8192. Bytes of HTTP protocol workspace allocated for objects. This space must be big enough for the entire HTTP protocol header and any edits done to it in the VCL code while it is cached. Minimum is 1024 bytes.   NB: This parameter may take quite some time to take (full) effect. ');
INSERT INTO parameter_info VALUES('overflow_max', '%', 'Default is 100. Percentage permitted overflow queue length.   This sets the ratio of queued requests to worker threads, above which sessions will be dropped instead of queued.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('ping_interval', 'seconds', 'Default is 3. Interval between pings from parent to child. Zero will disable pinging entirely, which makes it possible to attach a debugger to the child.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('pipe_timeout', 'seconds', 'Default is 60. Idle timeout for PIPE sessions. If nothing have been received in either direction for this many seconds, the session is closed. ');
INSERT INTO parameter_info VALUES('prefer_ipv6', 'bool', 'Default is off. Prefer IPv6 address when connecting to backends which have both IPv4 and IPv6 addresses. ');
INSERT INTO parameter_info VALUES('purge_dups', 'bool', 'Default is off. Detect and eliminate duplicate purges. ');
INSERT INTO parameter_info VALUES('purge_hash', 'bool', 'Default is off. Enable purge.hash command. NB: this increases storage requirement per object by the length of the hash string.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('rush_exponent', 'requests per request', 'Default is 3. How many parked request we start for each completed request on the object. NB: Even with the implict delay of delivery, this parameter controls an exponential increase in number of worker threads.     NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('send_timeout', 'seconds', 'Default is 600. Send timeout for client connections. If no data has been sent to the client in this many seconds, the session is closed. See setsockopt(2) under SO_SNDTIMEO for more information.   NB: This parameter may take quite some time to take (full) effect. ');
INSERT INTO parameter_info VALUES('sess_timeout', 'seconds', 'Default is 5. Idle timeout for persistent sessions. If a HTTP request has not been received in this many seconds, the session is closed. ');
INSERT INTO parameter_info VALUES('sess_workspace', 'bytes', 'Default is 16384. Bytes of HTTP protocol workspace allocated for sessions. This space must be big enough for the entire HTTP protocol header and any edits done to it in the VCL code. Minimum is 1024 bytes.   NB: This parameter may take quite some time to take (full) effect. ');
INSERT INTO parameter_info VALUES('session_linger', 'ms', 'Default is 0. How long time the workerthread lingers on the session to see if a new request appears right away. If sessions are reused, as much as half of all reuses happen within the first 100 msec of the previous request completing. Setting this too high results in worker threads not doing anything for their keep, setting it too low just means that more sessions take a detour around the waiter.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('shm_reclen', 'bytes', 'Default is 255. Maximum number of bytes in SHM log record. Maximum is 65535 bytes. ');
INSERT INTO parameter_info VALUES('shm_workspace', 'bytes', 'Default is 8192. Bytes of shmlog workspace allocated for worker threads. If too big, it wastes some ram, if too small it causes needless flushes of the SHM workspace. These flushes show up in stats as "SHM flushes due to overflow". Minimum is 4096 bytes.   NB: This parameter may take quite some time to take (full) effect. ');
INSERT INTO parameter_info VALUES('srcaddr_hash', 'buckets', 'Default is 1049. Number of source address hash buckets. Powers of two are bad, prime numbers are good.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('srcaddr_ttl', 'seconds', 'Default is 30. Lifetime of srcaddr entries. Zero will disable srcaddr accounting entirely.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_add_delay', 'milliseconds', 'Default is 20. Wait at least this long between creating threads.   Setting this too long results in insuffient worker threads.   Setting this too short increases the risk of worker thread pile-up.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_add_threshold', 'requests', 'Default is 2. Overflow threshold for worker thread creation.   Setting this too low, will result in excess worker threads, which is generally a bad idea.   Setting it too high results in insuffient worker threads.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_fail_delay', 'milliseconds', 'Default is 200. Wait at least this long after a failed thread creation before trying to create another thread.   Failure to create a worker thread is often a sign that  the end is near, because the process is running out of RAM resources for thread stacks. This delay tries to not rush it on needlessly.   If thread creation failures are a problem, check that thread_pool_max is not too high.   It may also help to increase thread_pool_timeout and thread_pool_min, to reduce the rate at which treads are destroyed and later recreated.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_max', 'threads', 'Default is 500. The maximum number of worker threads in all pools combined.   Do not set this higher than you have to, since excess worker threads soak up RAM and CPU and generally just get in the way of getting work done.   NB: This parameter may take quite some time to take (full) effect.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_min', 'threads', 'Default is 5. The minimum number of threads in each worker pool.   Increasing this may help ramp up faster from low load situations where threads have expired.   Minimum is 2 threads.   NB: This parameter may take quite some time to take (full) effect.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_purge_delay', 'milliseconds', 'Default is 1000. Wait this long between purging threads.   This controls the decay of thread pools when idle(-ish).   Minimum is 100 milliseconds.   NB: This parameter may take quite some time to take (full) effect.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pool_timeout', 'seconds', 'Default is 300. Thread idle threshold.   Threads in excess of thread_pool_min, which have been idle for at least this long are candidates for purging.   Minimum is 1 second.   NB: This parameter may take quite some time to take (full) effect.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('thread_pools', 'pools', 'Default is 2. Number of worker thread pools.   Increasing number of worker pools decreases lock contention.   Too many pools waste CPU and RAM resources, and more than one pool for each CPU is probably detrimal to performance.   Can be increased on the fly, but decreases require a restart to take effect.   NB: This parameter may take quite some time to take (full) effect.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome. ');
INSERT INTO parameter_info VALUES('child_user', '', 'Default is . The unprivileged user to run as.  Setting this will also set "group" to the specified user''s primary group.   NB: This parameter will not take any effect until the child process has been restarted. ');
INSERT INTO parameter_info VALUES('vcl_trace', 'bool', 'Default is off. Trace VCL execution in the shmlog. Enabling this will allow you to see the path each request has taken through the VCL program. This generates a lot of logrecords so it is off by default. ');
INSERT INTO parameter_info VALUES('waiter', '', 'Default is default. Select the waiter kernel interface.   NB: We do not know yet if it is a good idea to change this parameter, or if the default value is even sensible.  Caution is advised, and feedback is most welcome.   NB: This parameter will not take any effect until the child process has been restarted. ');

