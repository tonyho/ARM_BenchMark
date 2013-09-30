/*
 * lat_open_close.c - close(open())
 *
 * Usage: lat_open_close [-C] [-P <parallelism] [-W <warmup>] [-N <repetitions>] size file
 *
 */
char	*id = "$Id$\n";

#include "bench.h"

#define	CHK(x)		if ((int)(x) == -1) { perror(#x); exit(1); }
#define DO_ABORT(x)    {perror(x); exit(1);}
#ifndef	MIN
#define	MIN(a, b)	((a) < (b) ? (a) : (b))
#endif

#define	TYPE	int
#define	MINSZ	(sizeof(TYPE) * 128)

void	*buf;		/* do the I/O here */
size_t	xfersize;	/* do it in units of this */
size_t	count;		/* bytes to move (can't be modified) */

typedef struct _state {
	char path[PATH_MAX];
	char filename[PATH_MAX];
	int fd;
	int qfd[2][10];
	int clone;
	int isolate;
	int write;
	int use_uid;
	int lock_uid;
} state_t;

void
initialize(iter_t iterations, void* cookie)
{
	state_t	*state = (state_t *) cookie;
	char path[PATH_MAX];
	int ret;
	int fd;
	int rw = state->write ? O_WRONLY: 0;
	if (iterations) return;

	/* Use isolated directories to eliminate locking contetion on path,
	 * from measurements */
	if (state->isolate) {
		sprintf(path, "%s/%d", state->path, benchmp_childid());
 		if (chdir(path))
			DO_ABORT("chdir() failed");
	} else {
		sprintf(path, "%s/%s", state->path, state->filename);
		strcpy(state->filename, path);
	}
	if (state->use_uid) {
		setegid(benchmp_childid_gid());
		seteuid(benchmp_childid_uid());
	}
	if (state->lock_uid) {
		if (state->lock_uid > sizeof(state->qfd[0]) / sizeof(int))
			state->lock_uid = sizeof(state->qfd[0]) / sizeof(int);
		ret = get_quota_n(state->filename,
				geteuid(), getegid(),
				state->qfd[0], state->lock_uid);
		if (ret)
			DO_ABORT("Cant get quota");
	}
	state->fd = -1;
	if (state->clone) {
		char buf[128];
		char* s;
		sprintf(buf, "%d", (int)getpid());
		s = (char*)malloc(strlen(state->filename) + strlen(buf) + 1);
		sprintf(s, "%s%d", state->filename, (int)getpid());
		strcpy(state->filename, s);
	}

	if (state->isolate || state->clone) {
		fd = open(state->filename, O_CREAT|rw, 0666);
		if (fd < 0)
			DO_ABORT("open");
		close(fd);
	}
}

void
time_with_open(iter_t iterations, void * cookie)
{
	state_t	*state = (state_t *) cookie;
	char	*filename = state->filename;
	int rw = state->write ? O_WRONLY: 0;
	int	fd;

	while (iterations-- > 0) {
		fd = open(filename, O_RDONLY | rw);
		close(fd);
	}
}

void
cleanup(iter_t iterations, void * cookie)
{
	state_t *state = (state_t *) cookie;
	int i;
	if (iterations) return;

	for (i = 0 ; i < state->lock_uid; i++) {
		close(state->qfd[0][i]);
		state->qfd[0][i] = -1;
	}
	if (state->isolate || state->clone)
		unlink(state->filename);
}

int
main(int ac, char **av)
{
	int	fd;
	state_t state;
	int	parallel = 1;
	int	warmup = 0;
	int	repetitions = -1;
	int	c;
	char	usage[1024];
	
	sprintf(usage,"[-C] [-P <parallelism>] [-W <warmup>] [-N <repetitions>]"
		" [-D <path>] [-I isolate_paths ] [-U uid/gid] \n"
		" [-L <lock_uid>] [-w <open for write>] <filename>\n");

	state.clone = 0;

	while (( c = getopt(ac, av, "P:W:N:L:D:CIUw")) != EOF) {
		switch(c) {
		case 'P':
			parallel = atoi(optarg);
			if (parallel <= 0) lmbench_usage(ac, av, usage);
			break;
		case 'W':
			warmup = atoi(optarg);
			break;
		case 'N':
			repetitions = atoi(optarg);
			break;
		case 'L':
			state.lock_uid = atoi(optarg);
			break;
		case 'D':
			strcpy(state.path, optarg);
			break;
		case 'C':
			state.clone = 1;
			break;
		case 'I':
			state.isolate = 1;
			break;
		case 'U':
			state.use_uid = 1;
			break;
		case 'w':
			state.write = 1;
			break;
		default:
			lmbench_usage(ac, av, usage);
			break;
		}
	}

	if (optind + 1 != ac) { /* should have three arguments left */
		lmbench_usage(ac, av, usage);
	}

	strcpy(state.filename,av[optind]);
	benchmp(initialize, time_with_open, cleanup,
			0, parallel, warmup, repetitions, &state);

	mili_op("res ", get_n(), parallel);
	return (0);
}
