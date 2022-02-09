# about

This project is a hardhat & dapp project. You can use either dapp.tools or hardhat to develop on it.


# tests

dapp.tools tests
```
dapp test
```

Hardhat tests require a node forking mainnet, you can configure this using the `.env` file
```
yarn hardhat test
```


# aludel factory

This factory allows to launch predefined Aludels (reward programs) in a decentralized way.

There's a hardhat task `launch-program` which performs a minimal proxy deploy of the selected aludel template, and let you initialize it with any set of parameters.

using `launch-program` task:
```
yarn hardhat launch-program \
  --alude-factory \
  --owner \
  --rewardPool 0xf016fa84d5f3a252409a63b5cb89b555a0d27ccf \
  --powerSwitch 0x89d2d92eace71977dd0b159062f8ec90ea64fc24 \
  --stakingToken 0xCD6bcca48069f8588780dFA274960F15685aEe0e \
  --rewardToken 0x88ACDd2a6425c3FaAE4Bc9650Fd7E27e0Bebb7aB \
  --rewardScalingFloor 1 \
  --rewardScalingCeiling 10 \
  --rewardScalingTime 1 \
```


