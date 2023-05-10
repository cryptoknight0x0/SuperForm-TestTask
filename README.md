# SuperForm ERC4626 Wrapper

## Installation

1. Clone the Repository

```properties
git clone https://github.com/capedcrusader11/SuperForm-TestTask.git

```

2. Add permissions to setup.sh

```properties
chmod +x ./setup.sh
```

## Usage

To run the tests run the bash script

```properties
./setup.sh
```

To explicitly run tests and see gas report run

```properties
forge test -vvv --gas-report
```

### Design Choices

1. I used inspiration from existing wrapper for [Compound](https://github.com/superform-xyz/super-vaults/blob/main/src/compound/CompoundV2ERC4626Wrapper.sol) and [Yield Daddy](https://github.com/timeless-fi/yield-daddy/tree/main/src/compound). For deploying and predeterming 
address for the contract i used OpenZeppelin's Library [Clone](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Clones.sol). I also used Minimal proxy to reduce the deployment cost greatly. To use Minimal proxy I had to fork Solmates version of ERC20 and ERC4626 and add initializer functions to make it upgradeable. Have used OpenZeppelin's [Initializable](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/Initializable.sol) 

In Below Imagae you can see that cost of deployment using createERC4626 is vastly reduced in comparision to a normal deployment.
![Gas Costs](/images/Gas.png)

2. Changes Made in Yield-daddy's test to support fork tests
  On running fork tests with the current implementation of yield-daddy's test, the following error was encountered:
Note : Ran the tests with `RUST_LOG=forge=trace,foundry_evm=trace,ethers=trace forge test --match-patch test/ERC4626StdTest.t.sol` you'll see the above error because it's making a lot of RPC requests since it's a fork test and the test hangs because stdstore to find the storage slot of a struct variable.
![Error](/images/RPC_Error.png)
Ref : https://github.com/foundry-rs/foundry/issues/4735 and https://github.com/foundry-rs/foundry/issues/4656
I tried pinning to a block number and use a fuzz seed to reduce the number of RPC calls, so that the subsequent invocations will be much fast since responses will be cached, but it didn't work because of the stdstore issue.
So, I overrode the `ERC4626.test.sol` 's `setUpVault` (this function sets up the initial shares and assets for individual users before each test) with the following changes :

1. **Introduction of `maxAssetPerUser`**: A new variable `maxAssetPerUser` is introduced, which calculates the maximum assets that can be allotted to each user. This is done by taking half of the total assets of the `userWithAssets` and dividing by `N` (the number of users). This is a significant alteration in the logic of the code, and done to ensure that no single user has an undue amount of assets.

2. **Introduction of `bound` function**: In Code 2, the `bound` function is used to limit the shares and assets of each user to a range between 100 and `maxAssetPerUser`.

3. **Use of `userWithAssets`: Introduced the `userWithAssets` variable (a user address that has some initial assets). The functionality support for vaults where `deal()` can't find the storage slot.


### Failing Tests

1. harves test
   The harvest test is failing due to Uniswap V3 router swap call not getting through. I am atttaching below picture from one of the tokens where 
   Uniswap UI cannot predict the expected amount out and price due to unavailablility of funds.

   ![Uniswap Router](/images/Uniswap_Router.png)

2. Ondo Tests are failing as we are not KYC'd i.e whitelisted for token transfers

   ![ONDO_ERROR](/images/ONDO_Error.png)


