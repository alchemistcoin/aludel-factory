
# Development

* Install foundry
* Install dependencies with yarn & forge update
* Compile the contracts: ```forge build```
* Run tests: ```forge test``` (you need to setup a RPC url in `foundry.toml`)


# aludel factory

This factory allows you to launch pre-deployed Aludels

There's a hardhat task `launch-program` which performs a minimal proxy deploy of the selected aludel template with a set of params to initialize it.

`launch-program` usage:
```
yarn hardhat launch-program \
  --aludel-factory 0xb3208a1287ccdf5718f2eB516FDdAa089a354360 \
  --owner $DEV_ADDRESS \
  --reward-pool 0x5d15d226303cb96ac2ea7f760a313ea6bb36c508 \
  --power-switch 0x6d07709a30fce07901b2a6d8e1d6e6ac17eb96de \
  --staking-token 0xe55687682fdf08265d1672ea0c91fa884ccd8955 \
  --reward-token 0xF6c1210Aca158bBD453A12604A03AeD2659ac0ef \
  --reward-scaling-floor 1 \
  --reward-scaling-ceiling 1 \
  --reward-scaling-time 1000 \
  --network rinkeby
```


