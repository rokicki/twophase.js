\def\mod{\mathop{mod}}
@s cubepos int
@s moveseq int
@s kocsymm int
@s permcube int
@s lookup_type int
@s map template

@* Introduction.
This is a solver for Rubik's Cube, using Herbert Kociemba's
two-phase algorithm.

@(twophasesm.cpp@>=
const char *BANNER =
   "This is small twophase 2.1, (C) 2010-2013 Tomas Rokicki.  All Rights Reserved." ;
#include "phase1prunesm.h"
#include "phase2prune.h"
#include <cstdio>
#include <map>
using namespace std ;
@<Data declarations@> @;
@<Utility functions@> @;
@<Solver class@> @;
int main(int argc, char *argv[]) {
   double progstart = walltime() ;
   duration() ;
   @<Parse arguments@> @;
   @<Initialize the program@> @;
   printf("Duration in main is %g\n", duration()) ;
   @<Handle the work@> @;
   @<Print summary@> @;
}

@ There is actually very little cube code in this program.  Almost all
the work is handled by the code in {\tt cubepos}, {\tt kocsymm},
{\tt phase1prunesm}, and {\tt phase2prune}; the code in this file is
predominantly bookkeeping, thread management, and the like.  The first
thing we take up is argument parsing.  Two arguments we know we
need up front include a verbosity level (the default is 1, but the
|-q| option makes it 0 and the |-v| option makes it 2), and a
thread count.

@<Data decl...@>=
int verbose = 1 ;
int numthreads = 1 ;

@ Parsing the arguments is boilerplate code.

@<Parse arguments@>=
while (argc > 1 && argv[1][0] == '-') {
   argc-- ;
   argv++ ;
   switch (argv[0][1]) {
case 'v': verbose++ ; break ;
case 'q': verbose = 0 ; break ;
case 't':
       if (sscanf(argv[1], "%d", &numthreads) != 1)
          error("! bad thread count argument") ;
       if (numthreads < 1 || numthreads > MAX_THREADS)
          error("! bad value for thread count") ;
       argc-- ;
       argv++ ;
       break ;
@<More arguments@> @;
default:
       error("! bad argument") ;
   }
}

@ The two-phase algorithm discovers solutions for each position of
decreasing distance.  Nominally, it runs forever for any single
position, always seeking a shorter position.  For this command-line
program there are two ways to limit its execution.  The first is to
limit the count of phase two probes that it will do per position.  The
next is to give a target solution length, such that if a solution of
that length or shorter is found, search will end.  We also track
how many total phase 2 probes there were.

@<Data decl...@>=
int target_length = 0 ;
int numpos = 100 ;
long long phase2limit = 300 ;
long long phase2total = 0LL ;
int depp1 = 7, depp2 = 9 ;

@ Both of these can be set from the command line.

@<More arguments@>=
case 'n':
   if (sscanf(argv[1], "%d", &numpos) != 1)
      error("! bad argument to -n") ;
   argc-- ;
   argv++ ;
   break ;
case 'M':
   if (sscanf(argv[1], "%lld", &phase2limit) != 1)
      error("! bad argument to -M") ;
   argc-- ;
   argv++ ;
   break ;
case 's': 
   if (sscanf(argv[1], "%d", &target_length) != 1)
      error("! bad argument to -s") ;
   if (target_length >= MAX_MOVES)
      target_length = MAX_MOVES - 1 ;
   argc-- ;
   argv++ ;
   break ;
case 'D':
   if (sscanf(argv[1], "%d", &depp1) != 1 ||
       sscanf(argv[2], "%d", &depp2) != 1)
      error("! bad argument to -D") ;
   argc -= 2 ;
   argv += 2 ;
   break ;

@ If neither of these two arguments are supplied, and we're
not running in verbose mode of 2 or greater, that's an
error because no output will be generated.

@<Initialize the program@>=
#ifdef REMOVEME
if (phase2limit >= 0xffffffffffffffLL && target_length == 0 &&
    verbose <= 1)
   error("! must specify -M, -s, or -v") ;
#endif

@ Usually the pruning tables are read from disk; if they don't exist,
they are created, and then written to disk.  If for some reason
you do not want to write the pruning tables to disk, you can use
the |-W| option to inhibit this.

@<Data...@>=
int skipwrite = 1 ;

@ Parsing this argument is easy.

@<More arguments@>=
case 'W': skipwrite++ ; break ;

@ If we are not running in quiet mode, we always print the banner as
the first part of initialization, before we load the pruning tables
since those can be slow.  We use both a phase 1 and a phase 2 pruning
table, so we initialize these in turn.

@<Initialize the program@>=
if (verbose) {
   printf("%s\n", BANNER) ;
   fflush(stdout) ;
}
phase1prunesm::init(depp1, skipwrite) ;
phase2prune::init(depp2, skipwrite) ;

@ We know that no solution will ever be longer than 32 moves.
The maximum distance from phase 1 is 12, and from phase 2 is 18.
We give it two extra just for good measure.

@<Utility...@>=
const int MAX_MOVES = 32 ;

@* Multithreading.
This program is intended to batch-solve many positions, rather than
just try to solve a particular position; for this reason, we use
threads and assign each position a thread (up to the maximum number of
threads specified by the user).  We do not solve a single position by
multiple threads, because of the complexity of managing communication
between the threads.  Thus, the solution work and all solution state is
maintained in a worker thread called a |twophasesolver|.  Each instance
of this class is small, so we preallocate all needed instances.  We
introduce a bit of padding so multiple threads don't fight over the
same cache lines.

@<Solver class@>=
class twophasesolver {
public: @/
   twophasesolver() {}
   cubepos pos ; // position to solve
   long long phase2probes ;
   int bestsol ; // length of the best solution
   int keepbound ; // lower value of what to keep
   int keepcounts[MAX_MOVES] ; // how many we've seen at each level
   int keepsum ; // sum of keepcounts from 0..keepbound
   int finished ; // set to true to terminate
   int curm ; // what orientation we are working on
   int solmap ; // the orientation the solution is in
   int seq ; // a serial number for this position
   @<Solver data@> @;
   @<Solver methods@> @;
   char pad[256] ;
} solvers[MAX_THREADS] ;

@ As we perform the searches, we place the moves we have needed into
the following array.

@<Solver data...@>=
unsigned char moves[MAX_MOVES] ;
unsigned char bestmoves[MAX_MOVES] ;
unsigned char expand3[40][4] ;

@ Our basic method for solving is here.  This initializes the
structure and starts the solution process.  The result is stored
in the fields of the solver structure.

@<Solver methods...@>=
void solve(int seqarg, cubepos &cp) {
   @<Initialize the solver@> @;
   @<Set up position invariants@> @;
   @<Solve one position@> @;
   @<Check and report solution@> @;
}

@ We initialize the fields we have declared so far.

@<Initialize the solver@>=
pos = cp ;
phase2probes = 0 ;
bestsol = MAX_MOVES ; // no solution found
keepbound = MAX_MOVES - 1 ; // keep anything this or shorter
finished = 0 ;
seq = seqarg ;
for (int i=0; i<40; i++)
   for (int j=0; j<4; j++)
      if (j == 3)
         expand3[i][j] = depp1 + 1 ;
      else
         expand3[i][j] = i + (j - i + 100) % 3 - 1 ;

@ This program uses a new, six-axis technique, to find a solution as
quickly as possible.  Normally the two-phase method just repeats phase
1 and phase 2 for increasing depths of phase 1 from the given input
position.  Some positions, however, are recalcitrant, and do not have
a nice short phase 1 solution leading to a short phase 2 solution.  To
make it more likely to find a solution quickly, we consider all three
axis reorientations.  Further, we also consider the inverse position
with all three axis reorientations, for a grand total of six different
starting positions.  For positions with symmetry or antisymmetry, we
do not want to cover the same ground multiple times, so we need to
calculate which of these six combinations are distinct.

For each of the six starting positions, we construct a |kocsymm| and a
|cubepos| to carry the state, calculate the minimum phase one depth,
and check which are unique.  We need to declare these fields.

@<Solver data...@>=
kocsymm kc6[6], kccanon6[6] ;
cubepos cp6[6] ;
permcube pc6[6] ;
int mindepth[6] ;
char uniq[6] ;
int minmindepth ;

@ Sometimes we want to run the twophase algorithm only working
with a specific subset of the possible axes.  This mask gives
that information.

@<Data...@>=
int axesmask = 63 ;

@ We use the -a option to set this.

@<More arguments@>=
case 'a':
   axesmask = atol(argv[1]) ;
   argv++ ;
   argc-- ;
   break ;

@ Initializing these is fairly easy.  We need to know what
reorientations change the axis; from |cubepos| we know that each group
of sixteen consecutive remappings maintains the up/down axis, so we
use reorientations 0, 16, and 32.  When comparing positions for
equality, we want to use the 16-way canonicalization that preserves
the up/down axis; the |kocsymm| canonicalization preserves this, so
we use this to preface a more involved comparison.

@<Set up position invariants@>=
minmindepth = MAX_MOVES ;
cubepos cpi, cp2 ;
pos.invert_into(cpi) ;
int ind = 0 ;
for (int inv=0; inv<2; inv++)
   for (int mm=0; mm<3; mm++, ind++) {
      int m = KOCSYMM * mm ;
      if (inv)
         cpi.remap_into(m, cp2) ;
      else
         pos.remap_into(m, cp2) ;
      cp6[ind] = cp2 ;
      kc6[ind] = kocsymm(cp2) ;
      pc6[ind] = permcube(cp2) ;
      kc6[ind].canon_into(kccanon6[ind]) ;
      mindepth[ind] = phase1prunesm::solve(kc6[ind]).size() ;
      if (mindepth[ind] < minmindepth)
         minmindepth = mindepth[ind] ;
      uniq[ind] = 1 & (axesmask >> ind) ;
      for (int i=0; i<ind; i++)
         if (uniq[i] && kccanon6[ind] == kccanon6[i] &&
                                                  sloweq(cp6[ind], cp6[i])) {
            uniq[ind] = 0 ;
            break ;
         }
   }

@ We need a utility method that does a slow comparison between two
|cubepos| and returns true if there's any reorientation, preserving the
up/down axis, of one that is the same as the other.

@<Utility...@>=
int sloweq(const cubepos &cp1, const cubepos &cp2) {
   cubepos cp3 ;
   for (int m=0; m<KOCSYMM; m++) {
      cp2.remap_into(m, cp3) ;
      if (cp1 == cp3)
         return 1 ;
   }
   return 0 ;
}

@ Once we have a minimum depth, we can start solving.

@<Solve one pos...@>=
for (int d=minmindepth; d <= keepbound && !finished; d++) {
   for (curm=0; curm<6; curm++)
      if (uniq[curm] && d <= keepbound && !finished && d >= mindepth[curm])
         solvep1(kc6[curm], pc6[curm], d, 0, mindepth[curm], CANONSEQSTART) ;
}

@ The phase one solver.

@<Solver methods@>=
void solvep1(const kocsymm &kc, const permcube &pc, int togo, int sofar,
             int curd, int canon) {
   if (togo == 0) {
      if (kc == identity_kc)
         solvep2(pc, sofar) ;
      return ;
   }
   if (finished)
      return ;
   togo-- ;
   kocsymm kc2 ;
   permcube pc2 ;
   int movemask = cubepos::cs_mask(canon) ;
   for (int mv=0; mv<NMOVES; mv++) {
      if (0 == ((movemask >> mv) & 1))
         continue ;
      kc2 = kc ;
      kc2.move(mv) ;
      int nd = expand3[curd][phase1prunesm::lookup(kc2)] ;
      if (nd <= togo && (togo == nd || togo + nd >= 5)) {
         pc2 = pc ;
         pc2.move(mv) ;
         moves[sofar] = mv ;
         int new_canon = cubepos::next_cs(canon, mv) ;
         solvep1(kc2, pc2, togo, sofar+1, nd, new_canon) ;
      }
   }
}

@ The phase two code just uses the phase two solver.

@<Solver methods@>=
void solvep2(const permcube &pc, int sofar) {
   phase2probes++ ;
   int d = phase2prune::lookup(pc) ;
   if (d + sofar <= keepbound) {
      moveseq ms = phase2prune::solve(pc, keepbound-sofar) ;
      if ((int)(ms.size()) + sofar <= keepbound &&
          (ms.size() > 0 || pc == identity_pc)) {
         int cursol = ms.size() + sofar ;
         for (unsigned int i=0; i<ms.size(); i++)
            moves[sofar+i] = ms[i] ;
         if (cursol < bestsol) {
            bestsol = cursol ;
            memcpy(bestmoves, moves, bestsol) ;
            solmap = curm ;
         }
         keepbound = bestsol - 1 ;
         if (bestsol <= target_length)
            finished = 1 ;
      }
   }
   if (phase2probes >= phase2limit && bestsol < MAX_MOVES)
      finished = 1 ;
}

@ When we have a solution, and we have decided to present it to the user,
we need to first remap it, and then check it.

@<Check and report solution@>=
moveseq sol ;
int m = cubepos::invm[(solmap%3)*KOCSYMM] ;
for (int i=0; i<bestsol; i++)
   sol.push_back(cubepos::move_map[m][bestmoves[i]]) ;
if (solmap >= 3)
   sol = cubepos::invert_sequence(sol) ;
cubepos cpt ;
for (unsigned int i=0; i<sol.size(); i++)
   cpt.move(sol[i]) ;
if (cpt != pos)
   error("! move sequence doesn't work") ;
report(pos, seq, phase2probes, sol) ;

@ When we display a solution, we give some basic statistics as
well as the solution itself.  If we missed a target, we display
the orignal position in Singmaster format as well.

@<Utility...@>=
void display(const cubepos &cp, int seq, long long phase2probes, moveseq sol) {
   phase2total += phase2probes ;
   if (verbose || (int)sol.size() > target_length) {
      printf("Solution %d len %d probes %lld\n", seq, (int)sol.size(), phase2probes) ;
      printf("%s\n", cubepos::moveseq_string(sol)) ;
      fflush(stdout) ;
   }
}

@* Reporting solutions.
We would like to report solutions in sequential order.  Yet, with
threads, they may have their solutions found in non-sequential order.
To manage this, we keep track of the most recently printed sequence,
and only print a solution if it is the most recent sequence.  If it
is not we queue it up and print it when the missing sequence shows.
We define a structure to hold the relevant information.  We also
define a couple of variables to contain statistics.

@<Data...@>=
class solution {
public: @/
   solution(const cubepos &cparg, int seqarg, long long p2parg,
            moveseq &solarg) {
      cp = cparg ;
      seq = seqarg ;
      phase2probes = p2parg ;
      moves = solarg ;
   }
   solution() {}
   cubepos cp ;
   int seq ;
   long long phase2probes ;
   moveseq moves ;
} ;
map<int, solution> queue ;
int next_sequence = 1 ;
int missed_target = 0 ;
int solved = 0 ;
int sumdist = 0 ;

@ Our reporting function does the main work, with the global lock.

@<Utility...@>=
void report(const cubepos &cp, int seq, long long phase2probes, moveseq sol) {
   get_global_lock() ;
   solved++ ;
   if ((int)sol.size() > target_length && target_length)
      missed_target++ ;
   sumdist += sol.size() ;
   if (seq == next_sequence) {
      display(cp, seq, phase2probes, sol) ;
      next_sequence++ ;
      while (queue.find(next_sequence) != queue.end()) {
         solution &s = queue[next_sequence] ;
         display(s.cp, s.seq, s.phase2probes, s.moves) ;
         queue.erase(next_sequence) ;
         next_sequence++ ;
      }
   } else {
      queue[seq] = solution(cp, seq, phase2probes, sol) ;
   }
   release_global_lock() ;
}

@ When we are all done, we print this summary.

@<Print summary@>=
printf("Solved %d sequences in %g seconds avg %g with %lld probes.\n",
   solved, duration(), sumdist/(double)numpos, phase2total) ;
printf("Completed in %g\n", walltime()-progstart) ;
exit(0) ;

@ Each thread has a routine that gets the next sequence to solve,
reports its solution, and moves on to the next, until there are
no more positions to solve.  This is that routine.

@<Solver methods@>=
void dowork() {
   cubepos cp ;
   int seq ;
   while (1) {
      seq = getwork(cp) ;
      if (seq <= 0)
         return ;
      solve(seq, cp) ;
   }
}

@ The getwork routine grabs the global lock, gets another input
line, parses it, and returns the position and the sequence.

@<Utility...@>=
int getwork(cubepos &cp) {
   static int input_seq = 1 ;
   if (input_seq > numpos)
      return -1 ;
   get_global_lock() ;
   cp.randomize() ;
   int r = input_seq++ ;
   release_global_lock() ;
   return r ;
}

@ Pthreads wants a function, not a method, so we define this routine
to help it out.

@<Solver methods@>=
static THREAD_RETURN_TYPE THREAD_DECLARATOR worker(void *s) {
   twophasesolver *solv = (twophasesolver *)s ;
   solv->dowork() ;
   return 0 ;
}

@ Our main body spawns the number of threads requested by the user
and waits for them to finish.  As a minor optimization, we use
the main thread for the thread zero work.

@<Handle the work...@>=
#ifdef THREADS
for (int ti=1; ti<numthreads; ti++)
   spawn_thread(ti, twophasesolver::worker, solvers+ti) ;
solvers[0].dowork() ;
for (int ti=1; ti<numthreads; ti++)
   join_thread(ti) ;
#else
solvers[0].dowork() ;
#endif
