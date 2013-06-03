#
#   Point this to your emscripten
#
CXX = ~/ens/emscripten/emcc
CXXFLAGS = -O4 -DHALF
EXXFLAGS = -O2 -DHALF -s TOTAL_MEMORY=120000000
LINKFLAGS =
OUTFLAG = -o

.SUFFIXES: .w .tex .pdf

default: all

WEBSOURCES = cubepos.w kocsymm.w phase1prunesm.w phase2prune.w twophasesm.w

BINARIES = twophasesm twophasesm.js twophasesm.html

PDFS = cubepos.pdf kocsymm.pdf phase1prunesm.pdf phase2prune.pdf twophasesm.pdf

all: $(BINARIES)

.w.cpp: ; ctangle $*

.w.tex: ; cweave $*

.tex.pdf: ; pdftex $*

.w.pdf: ; cweave $* && pdftex $*

cubepos.cpp cubepos.h cubepos_test.cpp: cubepos.w

kocsymm.cpp kocsymm.h kocsymm_test.cpp: kocsymm.w

phase2prune.cpp phase2prune.h: phase2prune.w

phase1prunesm.cpp phase1prunesm.h: phase1prunesm.w

twophasesm.js: twophasesm.cpp phase1prunesm.cpp phase1prunesm.h phase2prune.cpp phase2prune.h kocsymm.cpp kocsymm.h cubepos.cpp cubepos.h
	$(CXX) $(EXXFLAGS) -DTWOPHASE_MAIN $(OUTFLAG) twophasesm.js twophasesm.cpp phase1prunesm.cpp phase2prune.cpp kocsymm.cpp cubepos.cpp $(LINKFLAGS)

twophasesm.html: twophasesm.cpp phase1prunesm.cpp phase1prunesm.h phase2prune.cpp phase2prune.h kocsymm.cpp kocsymm.h cubepos.cpp cubepos.h
	$(CXX) $(EXXFLAGS) -DTWOPHASE_MAIN $(OUTFLAG) twophasesm.html twophasesm.cpp phase1prunesm.cpp phase2prune.cpp kocsymm.cpp cubepos.cpp $(LINKFLAGS)

twophasesm: twophasesm.cpp phase1prunesm.cpp phase1prunesm.h phase2prune.cpp phase2prune.h kocsymm.cpp kocsymm.h cubepos.cpp cubepos.h
	g++ $(CXXFLAGS) -DTWOPHASE_MAIN $(OUTFLAG) twophasesm twophasesm.cpp phase1prunesm.cpp phase2prune.cpp kocsymm.cpp cubepos.cpp $(LINKFLAGS)
