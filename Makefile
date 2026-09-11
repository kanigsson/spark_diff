GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
JOBS ?= 4

.PHONY: all test test-contracts prove flow
all:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)

test: all
	bin/test_diff
	python3 tests/test_cli.py

test-contracts:
	$(GPRBUILD) -P tools.gpr -XDIFF_BUILD=checks -j$(JOBS)
	bin/checks/test_diff
	DIFF_BIN=bin/checks/spark-diff python3 tests/test_cli.py

flow:
	$(GNATPROVE) -P spark_diff.gpr --mode=flow -j$(JOBS)

prove:
	$(GNATPROVE) -P spark_diff.gpr --level=2 --timeout=20 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)
