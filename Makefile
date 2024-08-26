
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

fbuild:
	@forge build

ftest:
	@forge test -vvvvv

fcoverage:
	@forge coverage

deploy:
	@forge script script/PlayerVsPlayer.s.sol:PlayerVsPlayerScript --rpc-url ${RPC} --private-key ${KEY} --broadcast