.PHONY: test

test:
	@test/test.sh

circleci:
	@circleci local execute
