#!/bin/bash

if ! pgrep -x "foundryup" > /dev/null
then
    echo "Foundryup is not installed. Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
else
    echo "Foundryup is already installed."
fi

foundryup
forge install

UNDERLYING=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 COMPTROLLER=0x95Af143a021DF745bc78e845b54591C53a8B3A51 \
USER=0x7066fb331a6932563369eE8cbd297856F75A3Bd5 forge test -vvv --gas-report

UNDERLYING=0x6B175474E89094C44Da98b954EedeAC495271d0F COMPTROLLER=0x95Af143a021DF745bc78e845b54591C53a8B3A51 \
USER=0x60FaAe176336dAb62e284Fe19B885B095d29fB7F forge test -vvv --gas-report

UNDERLYING=0xdAC17F958D2ee523a2206206994597C13D831ec7 COMPTROLLER=0x95Af143a021DF745bc78e845b54591C53a8B3A51 \
USER=0x0162Cd2BA40E23378Bf0FD41f919E1be075f025F forge test -vvv --gas-report

UNDERLYING=0x853d955aCEf822Db058eb8505911ED77F175b99e COMPTROLLER=0x95Af143a021DF745bc78e845b54591C53a8B3A51 \
USER=0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2 forge test -vvv --gas-report

UNDERLYING=0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92 COMPTROLLER=0x95Af143a021DF745bc78e845b54591C53a8B3A51 \
USER=0x1A8c53147E7b61C015159723408762fc60A34D17 forge test -vvv --gas-report