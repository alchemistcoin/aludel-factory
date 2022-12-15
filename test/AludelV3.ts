import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { deployments, ethers } from "hardhat";
import {
  BigNumber,
  BigNumberish,
  Contract,
  ContractFactory,
  Wallet,
} from "ethers";
import { LogDescription } from "ethers/lib/utils";
import { TransactionResponse } from "@ethersproject/abstract-provider";
import {
  createInstance,
  deployContract,
  getTimestamp,
  increaseTime,
  deployERC20,
} from "./setup";
import { AludelFactory__factory, AludelV3 } from "../typechain-types";
import { AbiCoder } from "@ethersproject/abi";
import {
  signPermission,
  populateEvents,
  getLatestTimestamp,
  AludelInitializationParams,
} from "./utils";
import chai from "chai";
import assert from "assert";

const { expect } = chai;

describe("AludelV3", function () {
  let accounts: SignerWithAddress[], admin: SignerWithAddress;
  let user: Wallet;

  let powerSwitchFactory: Contract,
    rewardPoolFactory: Contract,
    vaultFactory: Contract,
    stakingToken: Contract,
    rewardToken: Contract,
    bonusToken: Contract,
    aludelFactory: Contract,
    aludelV3Template: Contract,
    powered: ContractFactory;

  let template: Contract;

  const mockTokenSupply = ethers.utils.parseEther("1000");
  const BASE_SHARES_PER_WEI = 1000000;
  const DAY = 24 * 3600;
  const YEAR = 365 * DAY;
  const defaultRewardScaling = { floor: 33, ceiling: 100, time: 60 * DAY };

  let amplInitialSupply: BigNumber;

  const stake = async (
    user: Wallet,
    aludel: Contract,
    vault: Contract,
    stakingToken: Contract,
    amount: BigNumberish,
    vaultNonce?: BigNumberish
  ) => {
    // sign permission
    const signedPermission = await signPermission(
      "Lock",
      vault,
      user,
      aludel.address,
      stakingToken.address,
      amount,
      vaultNonce
    );
    // stake on aludel
    return aludel.stake(vault.address, amount, signedPermission);
  };

  const unstakeAndClaim = async (
    user: Wallet,
    aludel: AludelV3,
    vault: Contract,
    stakingToken: Contract,
    indices: Array<BigNumberish>,
    amounts: Array<BigNumberish>,
    vaultNonce?: BigNumberish
  ) => {
    // sign permission
    const signedPermission = await signPermission(
      "Unlock",
      vault,
      user,
      aludel.address,
      stakingToken.address,
      amounts.reduce(
        (i, prev) => BigNumber.from(i).add(prev),
        BigNumber.from(0)
      ),
      vaultNonce
    );
    // unstake on aludel
    return aludel.unstakeAndClaim(
      vault.address,
      indices,
      amounts,
      signedPermission
    );
  };

  function calculateExpectedReward(
    stakeAmount: BigNumber,
    stakeDuration: BigNumberish,
    rewardAvailable: BigNumber,
    otherStakeUnits: BigNumberish,
    rewardScaling: { floor: number; ceiling: number; time: number }
  ) {
    const stakeUnits = stakeAmount.mul(stakeDuration);
    const baseReward = rewardAvailable
      .mul(stakeUnits)
      .div(stakeUnits.add(otherStakeUnits));
    // FIXME this makes the case where floor == ceiling still different from
    // not having rewardScaling at all, and I think that isn't the case in
    // the smart contract, but we should check it and update this function
    // accordingly. What I did in this case is to set the floor and ceiling
    // to 100 for the time being so I can deal with one problem at a time
    const minReward = baseReward.mul(rewardScaling.floor).div(100);
    const bonusReward = baseReward
      .mul(rewardScaling.ceiling - rewardScaling.floor)
      .mul(stakeDuration)
      .div(rewardScaling.time)
      .div(100);
    return stakeDuration >= rewardScaling.time
      ? baseReward
      : minReward.add(bonusReward);
  }

  async function launchProgram(
    startTime: BigNumberish,
    _bonusTokens: Contract[],
    owner: SignerWithAddress,
    args: AludelInitializationParams
  ): Promise<AludelV3> {
    const deployParams = new AbiCoder().encode(
      [
        "address",
        "address",
        "address",
        "address",
        "address",
        "uint256",
        "uint256",
        "uint256",
      ],
      args
    );

    const factory = AludelFactory__factory.connect(
      aludelFactory.address,
      admin
    );
    const launchArguments = [
      aludelV3Template.address,
      "program name",
      "protocol://program.url",
      startTime,
      vaultFactory.address,
      _bonusTokens.map((t: Contract) => t.address),
      owner.address,
      deployParams,
    ];
    const address = await (factory.callStatic as any).launch(
      ...launchArguments
    );
    const tx = await (factory as any).launch(...launchArguments);
    await tx.wait();
    const contract = await ethers.getContractAt("AludelV3", address, owner);
    return contract as AludelV3;
  }

  const subtractFundingFee = (amount: BigNumber) => {
    return amount.div(10000).mul(9900);
  };

  beforeEach(async function () {
    await deployments.fixture(["templates"], {
      keepExistingDeployments: true,
    });
    accounts = await ethers.getSigners();
    admin = accounts[1];
    user = Wallet.createRandom().connect(ethers.provider);
    await accounts[2].sendTransaction({
      to: user.address,
      value: (await accounts[2].getBalance()).mul(9).div(10),
    });
    powered = await ethers.getContractFactory(
      "src/contracts/powerSwitch/Powered.sol:Powered"
    );
    powerSwitchFactory = await deployContract(
      "src/contracts/powerSwitch/PowerSwitchFactory.sol:PowerSwitchFactory"
    );
    rewardPoolFactory = await deployContract("RewardPoolFactory");
    template = await deployContract("Crucible");

    // deploy factory
    vaultFactory = await deployContract("CrucibleFactory", [template.address]);

    // deploy mock tokens
    stakingToken = await deployERC20(admin, mockTokenSupply);
    rewardToken = await deployERC20(admin, mockTokenSupply);

    amplInitialSupply = mockTokenSupply;

    bonusToken = await deployERC20(admin, mockTokenSupply);

    const fixtures = await deployments.fixture(["AludelFactory", "templates"]);
    aludelFactory = await ethers.getContractAt(
      "AludelFactory",
      fixtures["AludelFactory"].address
    );
    aludelV3Template = await ethers.getContractAt(
      "AludelV3",
      fixtures["AludelV3"].address
    );
  });

  describe("initialize", function () {
    const buildParams = (floor: number, ceiling: number, time: number) => {
      const deployParams = new AbiCoder().encode(
        [
          "address",
          "address",
          "address",
          "address",
          "address",
          "uint256",
          "uint256",
          "uint256",
        ],
        [
          rewardPoolFactory.address,
          powerSwitchFactory.address,
          stakingToken.address,
          rewardToken.address,
          ethers.constants.AddressZero,
          floor,
          ceiling,
          time,
        ]
      );
      return [
        aludelV3Template.address,
        "program name",
        "protocol://program.url",
        0,
        vaultFactory.address,
        [],
        admin.address,
        deployParams,
      ];
    };
    describe("when rewardScaling.floor > rewardScaling.ceiling", function () {
      it("should fail", async function () {
        try {
          await aludelFactory.launch(
            ...buildParams(
              defaultRewardScaling.ceiling + 1,
              defaultRewardScaling.ceiling,
              defaultRewardScaling.time
            )
          );
          assert(false, "transaction didnt fail as expected");
        } catch (error: unknown) {
          expect((error as { data: string }).data).to.eq(
            "0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000418084af300000000000000000000000000000000000000000000000000000000",
            "transaction didnt fail as expected"
          );
        }
      });
    });

    describe("when rewardScalingTime = 0", function () {
      it("should fail", async function () {
        try {
          await aludelFactory.launch(
            ...buildParams(
              defaultRewardScaling.floor,
              defaultRewardScaling.ceiling,
              0
            )
          );
          assert(false, "transaction didnt fail as expected");
        } catch (error: unknown) {
          expect((error as { data: string }).data).to.eq(
            "0x08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000048c648c8500000000000000000000000000000000000000000000000000000000",
            "transaction didnt fail as expected"
          );
        }
      });
    });

    describe("when parameters are valid", function () {
      it("should set contract variables", async function () {
        const args = [
          rewardPoolFactory.address,
          powerSwitchFactory.address,
          stakingToken.address,
          rewardToken.address,
          ethers.constants.AddressZero,
          defaultRewardScaling.floor,
          defaultRewardScaling.ceiling,
          defaultRewardScaling.time,
        ];

        const aludel = await launchProgram(0, [], admin, args);

        expect(aludel).is.not.undefined;

        const data = await aludel.getAludelData();

        expect(data.stakingToken).to.eq(stakingToken.address);
        expect(data.rewardToken).to.eq(rewardToken.address);
        expect(data.rewardPool).to.not.eq(ethers.constants.AddressZero);
        expect(data.rewardScaling.floor).to.eq(33);
        expect(data.rewardScaling.ceiling).to.eq(100);
        expect(data.rewardSharesOutstanding).to.eq(0);
        expect(data.totalStake).to.eq(0);
        expect(data.totalStakeUnits).to.eq(0);
        expect(data.lastUpdate).to.eq(0);
        expect(data.rewardSchedules).to.deep.eq([]);
        expect(await aludel.getBonusTokenSetLength()).to.eq(0);
        expect(await aludel.owner()).to.eq(admin.address);
        expect(await aludel.getPowerSwitch()).to.not.eq(
          ethers.constants.AddressZero
        );
        expect(await aludel.getPowerController()).to.eq(admin.address);
        expect(await aludel.isOnline()).to.eq(true);
        expect(await aludel.isOffline()).to.eq(false);
        expect(await aludel.isShutdown()).to.eq(false);
      });
    });
  });

  describe("admin functions", function () {
    let aludel: AludelV3, powerSwitch: Contract, rewardPool: Contract;
    beforeEach(async function () {
      const args = [
        rewardPoolFactory.address,
        powerSwitchFactory.address,
        stakingToken.address,
        rewardToken.address,
        ethers.constants.AddressZero,
        defaultRewardScaling.floor,
        defaultRewardScaling.ceiling,
        defaultRewardScaling.time,
      ];
      aludel = await launchProgram(0, [], admin, args);

      powerSwitch = await ethers.getContractAt(
        "alchemist/contracts/aludel/PowerSwitch.sol:PowerSwitch",
        await aludel.getPowerSwitch()
      );
      rewardPool = await ethers.getContractAt(
        "RewardPool",
        (
          await aludel.getAludelData()
        ).rewardPool
      );
    });
    describe("fundAludel", function () {
      describe("with insufficient approval", function () {
        it("should fail", async function () {
          await expect(aludel.connect(admin).fund(amplInitialSupply, YEAR)).to
            .be.reverted;
        });
      });
      describe("with duration of zero", function () {
        it("should fail", async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, amplInitialSupply);
          await expect(
            aludel.connect(admin).fund(amplInitialSupply, 0)
          ).to.be.revertedWithCustomError(aludel, "InvalidDuration");
        });
      });
      describe("as user", function () {
        it("should fail", async function () {
          await rewardToken
            .connect(admin)
            .transfer(user.address, amplInitialSupply);
          await rewardToken
            .connect(user)
            .approve(aludel.address, amplInitialSupply);
          await expect(
            aludel.connect(user).fund(amplInitialSupply, YEAR)
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });
      });
      describe("when offline", function () {
        it("should fail", async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, amplInitialSupply);
          await powerSwitch.connect(admin).powerOff();
          await expect(
            aludel.connect(admin).fund(amplInitialSupply, YEAR)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("when shutdown", function () {
        it("should fail", async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, amplInitialSupply);
          await powerSwitch.connect(admin).emergencyShutdown();
          await expect(
            aludel.connect(admin).fund(amplInitialSupply, YEAR)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("when online", function () {
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, amplInitialSupply);
        });
        describe("at first funding", function () {
          it("should succeed", async function () {
            await aludel.connect(admin).fund(amplInitialSupply, YEAR);
          });
          it("should update state correctly", async function () {
            await aludel.connect(admin).fund(amplInitialSupply, YEAR);

            const data = await aludel.getAludelData();

            expect(data.rewardSharesOutstanding).to.eq(
              subtractFundingFee(amplInitialSupply).mul(BASE_SHARES_PER_WEI)
            );
            expect(data.rewardSchedules.length).to.eq(1);
            expect(data.rewardSchedules[0].duration).to.eq(YEAR);
            expect(data.rewardSchedules[0].start).to.eq(await getTimestamp());
            expect(data.rewardSchedules[0].shares).to.eq(
              subtractFundingFee(amplInitialSupply).mul(BASE_SHARES_PER_WEI)
            );
          });
          it("should emit event", async function () {
            await expect(aludel.connect(admin).fund(amplInitialSupply, YEAR))
              .to.emit(aludel, "AludelFunded")
              .withArgs(subtractFundingFee(amplInitialSupply), YEAR);
          });
          it("should transfer tokens", async function () {
            await expect(aludel.connect(admin).fund(amplInitialSupply, YEAR))
              .to.emit(rewardToken, "Transfer")
              .withArgs(
                admin.address,
                rewardPool.address,
                subtractFundingFee(amplInitialSupply)
              );
          });
        });
        describe("at second funding", function () {
          beforeEach(async function () {
            await aludel.connect(admin).fund(amplInitialSupply.div(2), YEAR);
          });
          describe("with no rebase", function () {
            it("should succeed", async function () {
              await aludel.connect(admin).fund(amplInitialSupply.div(2), YEAR);
            });
            it("should update state correctly", async function () {
              await aludel.connect(admin).fund(amplInitialSupply.div(2), YEAR);

              const data = await aludel.getAludelData();

              expect(data.rewardSharesOutstanding).to.eq(
                subtractFundingFee(amplInitialSupply).mul(BASE_SHARES_PER_WEI)
              );
              expect(data.rewardSchedules.length).to.eq(2);
              expect(data.rewardSchedules[0].duration).to.eq(YEAR);
              expect(data.rewardSchedules[0].start).to.eq(
                (await getTimestamp()) - 1
              );
              expect(data.rewardSchedules[0].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
              expect(data.rewardSchedules[1].duration).to.eq(YEAR);
              expect(data.rewardSchedules[1].start).to.eq(await getTimestamp());
              expect(data.rewardSchedules[1].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
            });
            it("should emit event", async function () {
              await expect(
                aludel.connect(admin).fund(amplInitialSupply.div(2), YEAR)
              )
                .to.emit(aludel, "AludelFunded")
                .withArgs(subtractFundingFee(amplInitialSupply).div(2), YEAR);
            });
            it("should transfer tokens", async function () {
              await expect(
                aludel.connect(admin).fund(amplInitialSupply.div(2), YEAR)
              )
                .to.emit(rewardToken, "Transfer")
                .withArgs(
                  admin.address,
                  rewardPool.address,
                  subtractFundingFee(amplInitialSupply).div(2)
                );
            });
          });
        });
        describe("after unstake", function () {
          const stakeAmount = ethers.utils.parseEther("100");

          let vault: Contract;
          beforeEach(async function () {
            vault = await createInstance("Crucible", vaultFactory, user);

            await stakingToken
              .connect(admin)
              .transfer(vault.address, stakeAmount);

            await stake(user, aludel, vault, stakingToken, stakeAmount);
            await increaseTime(defaultRewardScaling.time);

            await rewardToken
              .connect(admin)
              .approve(aludel.address, amplInitialSupply);
            await aludel
              .connect(admin)
              .fund(amplInitialSupply.div(2), defaultRewardScaling.time);
          });
          describe("with partial rewards exausted", function () {
            beforeEach(async function () {
              await increaseTime(defaultRewardScaling.time / 2);
              await unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              );
            });
            it("should succeed", async function () {
              await aludel
                .connect(admin)
                .fund(amplInitialSupply.div(2), defaultRewardScaling.time);
            });
            it("should update state correctly", async function () {
              await aludel
                .connect(admin)
                .fund(amplInitialSupply.div(2), defaultRewardScaling.time);

              const data = await aludel.getAludelData();

              expect(data.rewardSharesOutstanding).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .mul(3)
                  .div(4)
              );
              expect(data.rewardSchedules.length).to.eq(2);
              expect(data.rewardSchedules[0].duration).to.eq(
                defaultRewardScaling.time
              );
              expect(data.rewardSchedules[0].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
              expect(data.rewardSchedules[1].duration).to.eq(
                defaultRewardScaling.time
              );
              expect(data.rewardSchedules[1].start).to.eq(await getTimestamp());
              expect(data.rewardSchedules[1].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
            });
            it("should emit event", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .fund(amplInitialSupply.div(2), defaultRewardScaling.time)
              )
                .to.emit(aludel, "AludelFunded")
                .withArgs(
                  subtractFundingFee(amplInitialSupply).div(2),
                  defaultRewardScaling.time
                );
            });
            it("should transfer tokens", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .fund(amplInitialSupply.div(2), defaultRewardScaling.time)
              )
                .to.emit(rewardToken, "Transfer")
                .withArgs(
                  admin.address,
                  rewardPool.address,
                  subtractFundingFee(amplInitialSupply).div(2)
                );
            });
          });
          describe("with full rewards exausted", function () {
            beforeEach(async function () {
              await increaseTime(defaultRewardScaling.time);
              await unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              );
            });
            it("should succeed", async function () {
              await aludel
                .connect(admin)
                .fund(amplInitialSupply.div(2), defaultRewardScaling.time);
            });
            it("should update state correctly", async function () {
              await aludel
                .connect(admin)
                .fund(amplInitialSupply.div(2), defaultRewardScaling.time);

              const data = await aludel.getAludelData();

              expect(data.rewardSharesOutstanding).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
              expect(data.rewardSchedules.length).to.eq(2);
              expect(data.rewardSchedules[0].duration).to.eq(
                defaultRewardScaling.time
              );
              expect(data.rewardSchedules[0].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
              expect(data.rewardSchedules[1].duration).to.eq(
                defaultRewardScaling.time
              );
              expect(data.rewardSchedules[1].start).to.eq(await getTimestamp());
              expect(data.rewardSchedules[1].shares).to.eq(
                subtractFundingFee(amplInitialSupply)
                  .mul(BASE_SHARES_PER_WEI)
                  .div(2)
              );
            });
            it("should emit event", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .fund(amplInitialSupply.div(2), defaultRewardScaling.time)
              )
                .to.emit(aludel, "AludelFunded")
                .withArgs(
                  subtractFundingFee(amplInitialSupply).div(2),
                  defaultRewardScaling.time
                );
            });
            it("should transfer tokens", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .fund(amplInitialSupply.div(2), defaultRewardScaling.time)
              )
                .to.emit(rewardToken, "Transfer")
                .withArgs(
                  admin.address,
                  rewardPool.address,
                  subtractFundingFee(amplInitialSupply).div(2)
                );
            });
          });
        });
      });
    });

    describe("isValidVault", function () {
      let vault: Contract;
      beforeEach(async function () {
        const args = [
          rewardPoolFactory.address,
          powerSwitchFactory.address,
          stakingToken.address,
          rewardToken.address,
          ethers.constants.AddressZero,
          defaultRewardScaling.floor,
          defaultRewardScaling.ceiling,
          defaultRewardScaling.time,
        ];
        aludel = await launchProgram(0, [], admin, args);
        vault = await createInstance("Crucible", vaultFactory, user);
      });
      describe("when vault from factory removed", function () {
        beforeEach(async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
        });
        it("should be false", async function () {
          expect(await aludel.isValidVault(vault.address)).to.be.false;
        });
      });
      describe("when vault not from factory registered", function () {
        let secondFactory: Contract;
        let secondVault: Contract;
        beforeEach(async function () {
          secondFactory = await deployContract("CrucibleFactory", [
            template.address,
          ]);
          secondVault = await createInstance("Crucible", secondFactory, user);
        });
        it("should be false", async function () {
          expect(await aludel.isValidVault(secondVault.address)).to.be.false;
        });
      });
      describe("when vaults from multiple factory registered", function () {
        let secondFactory: Contract;
        let secondVault: Contract;
        beforeEach(async function () {
          secondFactory = await deployContract("CrucibleFactory", [
            template.address,
          ]);
          secondVault = await createInstance("Crucible", secondFactory, user);
          await aludel
            .connect(admin)
            .registerVaultFactory(secondFactory.address);
        });
        it("should be true", async function () {
          expect(await aludel.isValidVault(vault.address)).to.be.true;
          expect(await aludel.isValidVault(secondVault.address)).to.be.true;
        });
      });
    });

    describe("registerVaultFactory", function () {
      let secondFactory: Contract;
      beforeEach(async function () {
        secondFactory = await deployContract("CrucibleFactory", [
          template.address,
        ]);
      });
      describe("as user", function () {
        it("should fail", async function () {
          await expect(
            aludel.connect(user).registerVaultFactory(vaultFactory.address)
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });
      });
      describe("when online", function () {
        it("should update state", async function () {
          expect(await aludel.getVaultFactorySetLength()).to.be.eq(1);
          expect(await aludel.getVaultFactoryAtIndex(0)).to.be.eq(
            vaultFactory.address
          );
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(secondFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRegistered")
            .withArgs(secondFactory.address);
        });
      });
      describe("when offline", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).powerOff();
        });
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(secondFactory.address);
        });
        it("should update state", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(secondFactory.address);

          expect(await aludel.getVaultFactorySetLength()).to.be.eq(2);
          expect(await aludel.getVaultFactoryAtIndex(0)).to.be.eq(
            vaultFactory.address
          );
          expect(await aludel.getVaultFactoryAtIndex(1)).to.be.eq(
            secondFactory.address
          );
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(secondFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRegistered")
            .withArgs(secondFactory.address);
        });
      });
      describe("when shutdown", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
        });
        it("should fail", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(vaultFactory.address)
          ).to.be.revertedWithCustomError(powered, "Powered_IsShutdown");
        });
      });
      describe("when already added", function () {
        it("should fail", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(vaultFactory.address)
          ).to.be.revertedWithCustomError(aludel, "VaultAlreadyRegistered");
        });
      });
      describe("when removed", function () {
        beforeEach(async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
        });
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(vaultFactory.address);
        });
        it("should update state", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(vaultFactory.address);

          expect(await aludel.getVaultFactorySetLength()).to.be.eq(1);
          expect(await aludel.getVaultFactoryAtIndex(0)).to.be.eq(
            vaultFactory.address
          );
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(vaultFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRegistered")
            .withArgs(vaultFactory.address);
        });
      });
      describe("with second factory", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(secondFactory.address);
        });
        it("should update state", async function () {
          await aludel
            .connect(admin)
            .registerVaultFactory(secondFactory.address);

          expect(await aludel.getVaultFactorySetLength()).to.be.eq(2);
          expect(await aludel.getVaultFactoryAtIndex(0)).to.be.eq(
            vaultFactory.address
          );
          expect(await aludel.getVaultFactoryAtIndex(1)).to.be.eq(
            secondFactory.address
          );
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).registerVaultFactory(secondFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRegistered")
            .withArgs(secondFactory.address);
        });
      });
    });
    describe("removeVaultFactory", function () {
      describe("as user", function () {
        it("should fail", async function () {
          await expect(
            aludel.connect(user).removeVaultFactory(vaultFactory.address)
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });
      });
      describe("when online", function () {
        it("should succeed", async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
        });
        it("should update state", async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);

          expect(await aludel.getVaultFactorySetLength()).to.be.eq(0);
          await expect(aludel.getVaultFactoryAtIndex(0)).to.be.reverted;
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).removeVaultFactory(vaultFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRemoved")
            .withArgs(vaultFactory.address);
        });
      });
      describe("when offline", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).powerOff();
        });
        it("should succeed", async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
        });
        it("should update state", async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);

          expect(await aludel.getVaultFactorySetLength()).to.be.eq(0);
          await expect(aludel.getVaultFactoryAtIndex(0)).to.be.reverted;
        });
        it("should emit event", async function () {
          await expect(
            aludel.connect(admin).removeVaultFactory(vaultFactory.address)
          )
            .to.emit(aludel, "VaultFactoryRemoved")
            .withArgs(vaultFactory.address);
        });
      });
      describe("when shutdown", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
        });
        it("should fail", async function () {
          await expect(
            aludel.connect(admin).removeVaultFactory(vaultFactory.address)
          ).to.be.revertedWithCustomError(powered, "Powered_IsShutdown");
        });
      });
      describe("when already removed", function () {
        beforeEach(async function () {
          // await aludel.connect(admin).registerVaultFactory(vaultFactory.address)
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
        });
        it("should fail", async function () {
          await expect(
            aludel.connect(admin).removeVaultFactory(vaultFactory.address)
          ).to.be.revertedWithCustomError(aludel, "VaultFactoryNotRegistered");
        });
      });
    });

    describe("registerBonusToken", function () {
      describe("as user", function () {
        it("should fail", async function () {
          await expect(
            aludel.connect(user).registerBonusToken(bonusToken.address)
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });
      });
      describe("when online", function () {
        describe("on first call", function () {
          describe("with address zero", function () {
            it("should fail", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .registerBonusToken(ethers.constants.AddressZero)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with aludel address", function () {
            it("should fail", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(aludel.address)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with staking token", function () {
            it("should fail", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(stakingToken.address)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with reward token", function () {
            it("should fail", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(rewardToken.address)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with rewardPool address", function () {
            it("should fail", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(rewardPool.address)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with one other bonus token", function () {
            it("should succeed", async function () {
              await aludel
                .connect(admin)
                .registerBonusToken(bonusToken.address);
            });
            it("should update state", async function () {
              await aludel
                .connect(admin)
                .registerBonusToken(bonusToken.address);
              expect(await aludel.getBonusTokenSetLength()).to.eq(1);
              expect(await aludel.getBonusTokenAtIndex(0)).to.eq(
                bonusToken.address
              );
            });
            it("should emit event", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(bonusToken.address)
              )
                .to.emit(aludel, "BonusTokenRegistered")
                .withArgs(bonusToken.address);
            });
          });
        });
        describe("with 50 other bonus tokens", () => {
          beforeEach(async () => {
            for (let i = 0; i < 50; i++) {
              const deployment = await deployContract("MockERC20", [
                admin.address,
                0,
              ]);
              aludel.connect(admin).registerBonusToken(deployment.address);
            }
          });
          it("should fail when adding the 51th", async function () {
            const deployment = await deployContract("MockERC20", [
              admin.address,
              0,
            ]);
            await expect(
              aludel.connect(admin).registerBonusToken(deployment.address)
            ).to.be.revertedWithCustomError(aludel, "MaxBonusTokensReached");
          });
        });
        describe("on second call", function () {
          beforeEach(async function () {
            await aludel.connect(admin).registerBonusToken(bonusToken.address);
          });
          describe("with same token", function () {
            it("should fail", async function () {
              await expect(
                aludel.connect(admin).registerBonusToken(bonusToken.address)
              ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
            });
          });
          describe("with different bonus token", function () {
            let secondBonusToken: Contract;
            beforeEach(async function () {
              secondBonusToken = await deployContract("MockERC20", [
                admin.address,
                mockTokenSupply,
              ]);
            });
            it("should succeed", async function () {
              await aludel
                .connect(admin)
                .registerBonusToken(secondBonusToken.address);
            });
            it("should update state", async function () {
              await aludel
                .connect(admin)
                .registerBonusToken(secondBonusToken.address);
              expect(await aludel.getBonusTokenSetLength()).to.eq(2);
              expect(await aludel.getBonusTokenAtIndex(0)).to.eq(
                bonusToken.address
              );
              expect(await aludel.getBonusTokenAtIndex(1)).to.eq(
                secondBonusToken.address
              );
            });
            it("should emit event", async function () {
              await expect(
                aludel
                  .connect(admin)
                  .registerBonusToken(secondBonusToken.address)
              )
                .to.emit(aludel, "BonusTokenRegistered")
                .withArgs(secondBonusToken.address);
            });
          });
        });
      });
      describe("when offline", function () {
        it("should fail", async function () {
          await powerSwitch.connect(admin).powerOff();
          await expect(
            aludel.connect(admin).registerBonusToken(bonusToken.address)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("when shutdown", function () {
        it("should fail", async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
          await expect(
            aludel.connect(admin).registerBonusToken(bonusToken.address)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
    });

    describe("rescueTokensFromRewardPool", function () {
      let otherToken: Contract;
      beforeEach(async function () {
        otherToken = await deployERC20(admin, mockTokenSupply);
        await otherToken
          .connect(admin)
          .transfer(rewardPool.address, mockTokenSupply);
        await aludel.connect(admin).registerBonusToken(bonusToken.address);
      });
      describe("as user", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(user)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply
              )
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });
      });
      describe("with reward token", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                rewardToken.address,
                admin.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with bonus token", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                bonusToken.address,
                admin.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with staking token", function () {
        beforeEach(async function () {
          await stakingToken
            .connect(admin)
            .transfer(rewardPool.address, mockTokenSupply);
        });
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(
              stakingToken.address,
              admin.address,
              mockTokenSupply
            );
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                stakingToken.address,
                admin.address,
                mockTokenSupply
              )
          )
            .to.emit(stakingToken, "Transfer")
            .withArgs(rewardPool.address, admin.address, mockTokenSupply);
        });
      });
      describe("with aludel as recipient", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                aludel.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with staking token as recipient", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                stakingToken.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with reward token as recipient", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                rewardToken.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with rewardPool as recipient", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                rewardPool.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with address 0 as recipient", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                ethers.constants.AddressZero,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(aludel, "InvalidAddress");
        });
      });
      describe("with other address as recipient", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(
              otherToken.address,
              user.address,
              mockTokenSupply
            );
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                user.address,
                mockTokenSupply
              )
          )
            .to.emit(otherToken, "Transfer")
            .withArgs(rewardPool.address, user.address, mockTokenSupply);
        });
      });
      describe("with zero amount", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(otherToken.address, admin.address, 0);
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(otherToken.address, admin.address, 0)
          )
            .to.emit(otherToken, "Transfer")
            .withArgs(rewardPool.address, admin.address, 0);
        });
      });
      describe("with partial amount", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(
              otherToken.address,
              admin.address,
              mockTokenSupply.div(2)
            );
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply.div(2)
              )
          )
            .to.emit(otherToken, "Transfer")
            .withArgs(
              rewardPool.address,
              admin.address,
              mockTokenSupply.div(2)
            );
        });
      });
      describe("with full amount", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(
              otherToken.address,
              admin.address,
              mockTokenSupply
            );
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply
              )
          )
            .to.emit(otherToken, "Transfer")
            .withArgs(rewardPool.address, admin.address, mockTokenSupply);
        });
      });
      describe("with excess amount", function () {
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply.mul(2)
              )
          ).to.be.reverted;
        });
      });
      describe("when online", function () {
        it("should succeed", async function () {
          await aludel
            .connect(admin)
            .rescueTokensFromRewardPool(
              otherToken.address,
              admin.address,
              mockTokenSupply
            );
        });
        it("should transfer tokens", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply
              )
          )
            .to.emit(otherToken, "Transfer")
            .withArgs(rewardPool.address, admin.address, mockTokenSupply);
        });
      });
      describe("when offline", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).powerOff();
        });
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("when shutdown", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
        });
        it("should fail", async function () {
          await expect(
            aludel
              .connect(admin)
              .rescueTokensFromRewardPool(
                otherToken.address,
                admin.address,
                mockTokenSupply
              )
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
    });
  });

  describe("user functions", function () {
    let aludel: AludelV3, powerSwitch: Contract, rewardPool: Contract;
    beforeEach(async function () {
      const args = [
        rewardPoolFactory.address,
        powerSwitchFactory.address,
        stakingToken.address,
        rewardToken.address,
        ethers.constants.AddressZero,
        defaultRewardScaling.floor,
        defaultRewardScaling.ceiling,
        defaultRewardScaling.time,
      ];
      aludel = await launchProgram(0, [], admin, args);

      // now vault factory is registered when the program is created
      powerSwitch = await ethers.getContractAt(
        "alchemist/contracts/aludel/PowerSwitch.sol:PowerSwitch",
        await aludel.getPowerSwitch()
      );
      rewardPool = await ethers.getContractAt(
        "RewardPool",
        (
          await aludel.getAludelData()
        ).rewardPool
      );
    });

    describe("stake", function () {
      const stakeAmount = mockTokenSupply.div(100);
      let vault: Contract;

      beforeEach(async function () {
        vault = await createInstance("Crucible", vaultFactory, user);
        await stakingToken.connect(admin).transfer(vault.address, stakeAmount);
      });
      describe("when offline", function () {
        it("should fail", async function () {
          await powerSwitch.connect(admin).powerOff();
          await expect(
            stake(user, aludel, vault, stakingToken, stakeAmount)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("when shutdown", function () {
        it("should fail", async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
          await expect(
            stake(user, aludel, vault, stakingToken, stakeAmount)
          ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
        });
      });
      describe("to invalid vault", function () {
        it("should fail", async function () {
          await aludel.connect(admin).removeVaultFactory(vaultFactory.address);
          await expect(
            stake(user, aludel, vault, stakingToken, stakeAmount)
          ).to.be.revertedWithCustomError(aludel, "InvalidVault");
        });
      });
      describe("with amount of zero", function () {
        it("should fail", async function () {
          await expect(
            stake(user, aludel, vault, stakingToken, "0")
          ).to.be.revertedWithCustomError(aludel, "NoAmountStaked");
        });
      });
      describe("with insufficient balance", function () {
        it("should fail", async function () {
          await expect(
            stake(user, aludel, vault, stakingToken, stakeAmount.mul(2))
          ).to.be.revertedWith("UniversalVault: insufficient balance");
        });
      });
      describe("when not funded", function () {
        it("should succeed", async function () {
          await stake(user, aludel, vault, stakingToken, stakeAmount);
        });
      });
      describe("when funded", function () {
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, amplInitialSupply);
          await aludel.connect(admin).fund(amplInitialSupply, YEAR);
        });
        describe("on first stake", function () {
          describe("as vault owner", function () {
            it("should succeed", async function () {
              await stake(user, aludel, vault, stakingToken, stakeAmount);
            });
            it("should update state", async function () {
              await stake(user, aludel, vault, stakingToken, stakeAmount);

              const aludelData = await aludel.getAludelData();
              const vaultData = await aludel.getVaultData(vault.address);

              expect(aludelData.totalStake).to.eq(stakeAmount);
              expect(aludelData.totalStakeUnits).to.eq(0);
              expect(aludelData.lastUpdate).to.eq(await getTimestamp());

              expect(vaultData.totalStake).to.eq(stakeAmount);
              expect(vaultData.stakes.length).to.eq(1);
              expect(vaultData.stakes[0].amount).to.eq(stakeAmount);
              expect(vaultData.stakes[0].timestamp).to.eq(await getTimestamp());
            });
            it("should emit event", async function () {
              await expect(
                stake(user, aludel, vault, stakingToken, stakeAmount)
              )
                .to.emit(aludel, "Staked")
                .withArgs(vault.address, stakeAmount);
            });
            it("should lock tokens", async function () {
              await expect(
                stake(user, aludel, vault, stakingToken, stakeAmount)
              )
                .to.emit(vault, "Locked")
                .withArgs(aludel.address, stakingToken.address, stakeAmount);
            });
          });
        });
        describe("on second stake", function () {
          beforeEach(async function () {
            await stake(user, aludel, vault, stakingToken, stakeAmount.div(2));
          });
          it("should succeed", async function () {
            await stake(user, aludel, vault, stakingToken, stakeAmount.div(2));
          });
          it("should update state", async function () {
            await stake(user, aludel, vault, stakingToken, stakeAmount.div(2));

            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            expect(aludelData.totalStake).to.eq(stakeAmount);
            expect(aludelData.totalStakeUnits).to.eq(stakeAmount.div(2));
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());

            expect(vaultData.totalStake).to.eq(stakeAmount);
            expect(vaultData.stakes.length).to.eq(2);
            expect(vaultData.stakes[0].amount).to.eq(stakeAmount.div(2));
            expect(vaultData.stakes[0].timestamp).to.eq(
              (await getTimestamp()) - 1
            );
            expect(vaultData.stakes[1].amount).to.eq(stakeAmount.div(2));
            expect(vaultData.stakes[1].timestamp).to.eq(await getTimestamp());
          });
          it("should emit event", async function () {
            await expect(
              stake(user, aludel, vault, stakingToken, stakeAmount.div(2))
            )
              .to.emit(aludel, "Staked")
              .withArgs(vault.address, stakeAmount.div(2));
          });
          it("should lock tokens", async function () {
            await expect(
              stake(user, aludel, vault, stakingToken, stakeAmount.div(2))
            )
              .to.emit(vault, "Locked")
              .withArgs(
                aludel.address,
                stakingToken.address,
                stakeAmount.div(2)
              );
          });
        });
        describe("when MAX_STAKES_PER_VAULT reached", function () {
          let quantity: number;
          beforeEach(async function () {
            quantity = (await aludel.MAX_STAKES_PER_VAULT()).toNumber();
            for (let index = 0; index < quantity; index++) {
              await stake(
                user,
                aludel,
                vault,
                stakingToken,
                stakeAmount.div(quantity)
              );
            }
          });
          it("should fail", async function () {
            await expect(
              stake(
                user,
                aludel,
                vault,
                stakingToken,
                stakeAmount.div(quantity)
              )
            ).to.be.revertedWithCustomError(aludel, "MaxStakesReached");
          });
        });
      });
      describe("when stakes reset", function () {
        beforeEach(async function () {
          await stake(user, aludel, vault, stakingToken, stakeAmount);
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should succeed", async function () {
          await stake(user, aludel, vault, stakingToken, stakeAmount);
        });
        it("should update state", async function () {
          await stake(user, aludel, vault, stakingToken, stakeAmount);

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.totalStake).to.eq(stakeAmount);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());

          expect(vaultData.totalStake).to.eq(stakeAmount);
          expect(vaultData.stakes.length).to.eq(1);
          expect(vaultData.stakes[0].amount).to.eq(stakeAmount);
          expect(vaultData.stakes[0].timestamp).to.eq(await getTimestamp());
        });
        it("should emit event", async function () {
          await expect(stake(user, aludel, vault, stakingToken, stakeAmount))
            .to.emit(aludel, "Staked")
            .withArgs(vault.address, stakeAmount);
        });
        it("should lock tokens", async function () {
          await expect(stake(user, aludel, vault, stakingToken, stakeAmount))
            .to.emit(vault, "Locked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
    });

    describe("unstake", function () {
      const stakeAmount = ethers.utils.parseEther("100");
      const fundingAmount = ethers.utils.parseUnits("1000", 9);
      const rewardAmount = subtractFundingFee(fundingAmount);

      describe("with default config", function () {
        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(defaultRewardScaling.time);
        });
        describe("when offline", function () {
          it("should fail", async function () {
            await powerSwitch.connect(admin).powerOff();
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
          });
        });
        describe("when shutdown", function () {
          it("should fail", async function () {
            await powerSwitch.connect(admin).emergencyShutdown();
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            ).to.be.revertedWithCustomError(powered, "Powered_NotOnline");
          });
        });
        describe("with invalid vault", function () {
          it("should succeed", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          });
        });
        describe("with permissioned not signed by owner", function () {
          it("should fail", async function () {
            await expect(
              unstakeAndClaim(
                Wallet.createRandom().connect(ethers.provider),
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            ).to.be.revertedWith("ERC1271: Invalid signature");
          });
        });
        describe("with amount of zero", function () {
          it("should fail", async function () {
            await expect(
              unstakeAndClaim(user, aludel, vault, stakingToken, [0], [0])
            ).to.be.revertedWithCustomError(aludel, "NoAmountUnstaked");
          });
        });
        describe("with amount greater than stakes", function () {
          it("should fail", async function () {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount.add(1)]
              )
            ).to.be.revertedWithCustomError(aludel, "InvalidAmountArray");
          });
        });
      });
      describe("with fully vested stake", function () {
        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(0);
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, rewardAmount);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, rewardAmount);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with partially vested stake", function () {
        const stakeDuration = defaultRewardScaling.time / 2;
        const expectedReward = calculateExpectedReward(
          stakeAmount,
          stakeDuration,
          rewardAmount,
          0,
          defaultRewardScaling
        );

        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(stakeDuration);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with floor and ceiling scaled up", function () {
        const stakeDuration = defaultRewardScaling.time / 2;
        const expectedReward = calculateExpectedReward(
          stakeAmount,
          stakeDuration,
          rewardAmount,
          0,
          defaultRewardScaling
        );

        let vault: Contract;
        beforeEach(async function () {
          const args = [
            rewardPoolFactory.address,
            powerSwitchFactory.address,
            stakingToken.address,
            rewardToken.address,
            ethers.constants.AddressZero,
            defaultRewardScaling.floor * 2,
            defaultRewardScaling.ceiling * 2,
            defaultRewardScaling.time,
          ];
          aludel = await launchProgram(0, [], admin, args);

          powerSwitch = await ethers.getContractAt(
            "alchemist/contracts/aludel/PowerSwitch.sol:PowerSwitch",
            await aludel.getPowerSwitch()
          );
          rewardPool = await ethers.getContractAt(
            "RewardPool",
            (
              await aludel.getAludelData()
            ).rewardPool
          );

          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(stakeDuration);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });

      describe("with floor and ceiling set to the same value", function () {
        let vault: Contract;
        const disabledRewardScaling = {
          floor: 100,
          ceiling: 100,
          time: 60 * DAY,
        };
        beforeEach(async function () {
          const args = [
            rewardPoolFactory.address,
            powerSwitchFactory.address,
            stakingToken.address,
            rewardToken.address,
            ethers.constants.AddressZero,
            disabledRewardScaling.floor,
            disabledRewardScaling.ceiling,
            disabledRewardScaling.time,
          ];
          aludel = await launchProgram(0, [], admin, args);

          powerSwitch = await ethers.getContractAt(
            "alchemist/contracts/aludel/PowerSwitch.sol:PowerSwitch",
            await aludel.getPowerSwitch()
          );
          rewardPool = await ethers.getContractAt(
            "RewardPool",
            (
              await aludel.getAludelData()
            ).rewardPool
          );

          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, disabledRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount.mul(10));
        });

        describe("GIVEN 3 individual stakes across the funding period", () => {
          const stakeDuration = disabledRewardScaling.time;
          let tx: Promise<TransactionResponse>;
          let events: Array<LogDescription>;
          let stakeTimestamps: Array<number>;
          const totalStakeUnitsCreated = BigNumber.from(
            "777600300000000000000000000"
          );
          const totalRewardSharesCreated =
            rewardAmount.mul(BASE_SHARES_PER_WEI);
          beforeEach(async () => {
            stakeTimestamps = [];
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            stakeTimestamps.push(await getLatestTimestamp());
            await increaseTime(stakeDuration / 2);
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            stakeTimestamps.push(await getLatestTimestamp());
            await increaseTime(stakeDuration / 2);
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            stakeTimestamps.push(await getLatestTimestamp());
          });

          describe("WHEN unstaking the first one", () => {
            const expectedReward = calculateExpectedReward(
              stakeAmount,
              stakeDuration,
              rewardAmount,
              // the only other stake adding shares is the middle one, which is staked for only half of the fund
              stakeAmount.mul(stakeDuration / 2),
              disabledRewardScaling
            );
            beforeEach(async () => {
              tx = unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              );
              events = populateEvents(
                [aludel.interface, stakingToken.interface, vault.interface],
                (await (await tx).wait()).logs
              );
            });

            it("THEN all of its rewards are realized", async () => {
              const rewardClaimedEvents = events.filter(
                (it) => it.name == "RewardClaimed"
              );
              expect(rewardClaimedEvents.length).to.eq(1);
              expect(rewardClaimedEvents[0].args.vault).to.eq(vault.address);
              expect(rewardClaimedEvents[0].args.token).to.eq(
                rewardToken.address
              );
              // 1% margin for smol time elapsed by other things
              expect(rewardClaimedEvents[0].args.amount).to.be.gt(
                expectedReward.mul(99).div(100)
              );
              expect(rewardClaimedEvents[0].args.amount).to.be.lt(
                expectedReward
              );
            });

            it("AND the correct amount of stakeUnits is burnt", async () => {
              // total stakeUnits are (30 * DAY ) * 10e20 + (60 * DAY) * 10e20
              // remember, stakeAmount = 10e20, and one stake was up for 30 days and the other for 60
              // the third stake is really small since it's up for only one second
              // this stake is the one live for 60 days, so 60*DAY*10e20 stakeUnits should be burnt
              const expectedStakeUnitsBurnt = stakeAmount.mul(60 * DAY);
              const aludelData = await aludel.getAludelData();
              // lil buffer since with every block the other stakes accrue one second worth of stakes
              expect(aludelData.totalStakeUnits).to.gte(
                totalStakeUnitsCreated
                  .sub(expectedStakeUnitsBurnt)
                  .mul(99)
                  .div(100)
              );
              expect(aludelData.totalStakeUnits).to.lte(
                totalStakeUnitsCreated.sub(expectedStakeUnitsBurnt)
              );
            });

            it("AND the correct amount of rewardShares is burnt", async () => {
              // total rewardShares are rewardAmount * BASE_SHARES_PER_WEI
              // reward shares that should be burnt for an unstake is the share of the total rewards that this unstake's rewards represent
              const expectedSharesBurnt = totalRewardSharesCreated
                .mul(expectedReward)
                .div(rewardAmount);
              const aludelData = await aludel.getAludelData();
              // lil buffer since with every block the other stakes accrue one second worth of stakes
              expect(aludelData.rewardSharesOutstanding).to.gte(
                totalRewardSharesCreated.sub(expectedSharesBurnt)
              );
              expect(aludelData.rewardSharesOutstanding).to.lte(
                totalRewardSharesCreated
                  .sub(expectedSharesBurnt)
                  .mul(101)
                  .div(100)
              );
            });

            it("AND the other two stakes are still present", async () => {
              const { stakes } = await aludel.getVaultData(vault.address);
              // this is a bit of clear-box testing, since the order in which
              // the stakes end up in the array doesn't really matter, just
              // that they are there, but I'd rather assert internal behaviour
              // than do a bunch of .find s, which I guesstimate would be more
              // fragile
              expect(stakes[0].timestamp).to.eq(stakeTimestamps[2]);
              expect(stakes[0].amount).to.eq(stakeAmount);
              expect(stakes[1].timestamp).to.eq(stakeTimestamps[1]);
              expect(stakes[1].amount).to.eq(stakeAmount);
            });
          });

          describe("WHEN unstaking the one in the middle", () => {
            const expectedReward = calculateExpectedReward(
              stakeAmount,
              stakeDuration / 2,
              rewardAmount,
              // the only other stake adding shares is the first one, which is staked for the entire fund period
              stakeAmount.mul(stakeDuration),
              disabledRewardScaling
            );
            beforeEach(async () => {
              tx = unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [1],
                [stakeAmount]
              );
              events = populateEvents(
                [aludel.interface, stakingToken.interface, vault.interface],
                (await (await tx).wait()).logs
              );
            });

            it("THEN half of the rewards from it are realized", async () => {
              const rewardClaimedEvents = events.filter(
                (it) => it.name == "RewardClaimed"
              );
              expect(rewardClaimedEvents.length).to.eq(1);
              expect(rewardClaimedEvents[0].args.vault).to.eq(vault.address);
              expect(rewardClaimedEvents[0].args.token).to.eq(
                rewardToken.address
              );
              // 1% margin for smol time elapsed by other things
              expect(rewardClaimedEvents[0].args.amount).to.be.gt(
                expectedReward.mul(99).div(100)
              );
              expect(rewardClaimedEvents[0].args.amount).to.be.lte(
                expectedReward
              );
            });

            it("AND the correct amount of stakeUnits is burnt", async () => {
              // total stakeUnits are (30 * DAY ) * 10e20 + (60 * DAY) * 10e20
              // remember, stakeAmount = 10e20, and one stake was up for 30 days and the other for 60
              // the third stake is really small since it's up for only one second
              // this stake is the one live for 30 days, so 30*DAY*10e20 stakeUnits should be burnt
              const expectedStakeUnitsBurnt = stakeAmount.mul(30 * DAY);
              const aludelData = await aludel.getAludelData();
              // lil buffer since with every block the other stakes accrue one second worth of stakes
              expect(aludelData.totalStakeUnits).to.gte(
                totalStakeUnitsCreated
                  .sub(expectedStakeUnitsBurnt)
                  .mul(99)
                  .div(100)
              );
              expect(aludelData.totalStakeUnits).to.lte(
                totalStakeUnitsCreated.sub(expectedStakeUnitsBurnt)
              );
            });

            it("AND the correct amount of rewardShares is burnt", async () => {
              // total rewardShares are rewardAmount * BASE_SHARES_PER_WEI
              // reward shares that should be burnt for an unstake is the share of the total rewards that this unstake's rewards represent
              const expectedSharesBurnt = totalRewardSharesCreated
                .mul(expectedReward)
                .div(rewardAmount);
              const aludelData = await aludel.getAludelData();
              // lil buffer since with every block the other stakes accrue one second worth of stakes
              expect(aludelData.rewardSharesOutstanding).to.gte(
                totalRewardSharesCreated.sub(expectedSharesBurnt)
              );
              expect(aludelData.rewardSharesOutstanding).to.lte(
                totalRewardSharesCreated
                  .sub(expectedSharesBurnt)
                  .mul(101)
                  .div(100)
              );
            });

            it("AND the other two stakes are still present", async () => {
              const { stakes } = await aludel.getVaultData(vault.address);
              // this is a bit of clear-box testing, since the order in which
              // the stakes end up in the array doesn't really matter, just
              // that they are there, but I'd rather assert internal behaviour
              // than do a bunch of .find s, which I guesstimate would be more
              // fragile
              expect(stakes[0].timestamp).to.eq(stakeTimestamps[0]);
              expect(stakes[0].amount).to.eq(stakeAmount);
              expect(stakes[1].timestamp).to.eq(stakeTimestamps[2]);
              expect(stakes[1].amount).to.eq(stakeAmount);
            });
            describe("AND WHEN unstaking the first one", () => {
              // the rewards already claimed by the first unstake should be subtracted
              const secondAvailableReward = rewardAmount.sub(expectedReward);
              const secondExpectedReward = calculateExpectedReward(
                stakeAmount,
                stakeDuration,
                secondAvailableReward,
                0, // the last stake is up for ~3 seconds, shouldn't accrue many shares
                disabledRewardScaling
              );
              beforeEach(async () => {
                tx = unstakeAndClaim(
                  user,
                  aludel,
                  vault,
                  stakingToken,
                  [0],
                  [stakeAmount]
                );
                events = populateEvents(
                  [aludel.interface, stakingToken.interface, vault.interface],
                  (await (await tx).wait()).logs
                );
              });

              it("THEN all of its rewards are realized", async () => {
                const rewardClaimedEvents = events.filter(
                  (it) => it.name == "RewardClaimed"
                );
                expect(rewardClaimedEvents.length).to.eq(1);
                expect(rewardClaimedEvents[0].args.vault).to.eq(vault.address);
                expect(rewardClaimedEvents[0].args.token).to.eq(
                  rewardToken.address
                );
                // 1% margin for smol time elapsed by other things
                expect(rewardClaimedEvents[0].args.amount).to.be.gt(
                  secondExpectedReward.mul(99).div(100)
                );
                expect(rewardClaimedEvents[0].args.amount).to.be.lt(
                  secondExpectedReward
                );
              });

              it("AND nearly all stakeUnits are burnt", async () => {
                const aludelData = await aludel.getAludelData();
                // only the stake untis for the last stake should remain, and
                // it should be 10^20(stakeAmount)*3(time elapsed by
                // auto-mining 3 blocks). This might give a false negative in a
                // slower computer.
                expect(aludelData.totalStakeUnits).to.lte(
                  ethers.utils.parseUnits("3", 20)
                );
              });

              it("AND nearly all rewardShares are burnt", async () => {
                const aludelData = await aludel.getAludelData();
                // lil buffer since with every block the last stake accrued one second worth of stakes
                expect(aludelData.rewardSharesOutstanding).to.lte(
                  ethers.utils.parseUnits("1", 12)
                );
              });

              it("AND the last stake is still present", async () => {
                const { stakes } = await aludel.getVaultData(vault.address);
                expect(stakes[0].timestamp).to.eq(stakeTimestamps[2]);
                expect(stakes[0].amount).to.eq(stakeAmount);
              });
            });
          });

          describe("WHEN unstaking the last one", () => {
            beforeEach(async () => {
              tx = unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [2],
                [stakeAmount]
              );
              events = populateEvents(
                [aludel.interface, stakingToken.interface, vault.interface],
                (await (await tx).wait()).logs
              );
            });

            it("THEN nearly no rewards are realized", async () => {
              const rewardClaimedEvents = events.filter(
                (it) => it.name == "RewardClaimed"
              );
              expect(rewardClaimedEvents.length).to.eq(1);
              expect(rewardClaimedEvents[0].args.vault).to.eq(vault.address);
              expect(rewardClaimedEvents[0].args.token).to.eq(
                rewardToken.address
              );
              // the stake was created and removed right away, at the end of
              // the fund period, so this shouldn't earn the user anything
              expect(rewardClaimedEvents[0].args.amount).to.be.gt(0);
              expect(rewardClaimedEvents[0].args.amount).to.be.lt(1000000);
            });

            it("AND the nearly no stakeUnits are burnt", async () => {
              const aludelData = await aludel.getAludelData();
              // lil buffer since with every block the other stakes accrue one second worth of stakes
              expect(aludelData.totalStakeUnits).to.gte(
                totalStakeUnitsCreated.mul(99).div(100)
              );
              expect(aludelData.totalStakeUnits).to.lte(totalStakeUnitsCreated);
            });

            it("AND nearly no rewardShares are burnt", async () => {
              const aludelData = await aludel.getAludelData();
              expect(aludelData.rewardSharesOutstanding).to.gte(
                totalRewardSharesCreated.mul(99).div(100)
              );
            });

            it("AND the other two stakes are still present", async () => {
              const { stakes } = await aludel.getVaultData(vault.address);
              // this is a bit of clear-box testing, since the order in which
              // the stakes end up in the array doesn't really matter, just
              // that they are there, but I'd rather assert internal behaviour
              // than do a bunch of .find s, which I guesstimate would be more
              // fragile
              expect(stakes[0].timestamp).to.eq(stakeTimestamps[0]);
              expect(stakes[0].amount).to.eq(stakeAmount);
              expect(stakes[1].timestamp).to.eq(stakeTimestamps[1]);
              expect(stakes[1].amount).to.eq(stakeAmount);
            });
          });
        });

        describe("WHEN a user stays for the entire rewardScaling.time", () => {
          const stakeDuration = disabledRewardScaling.time;
          const rewardAmount = subtractFundingFee(fundingAmount);
          let tx: Promise<TransactionResponse>;
          beforeEach(async () => {
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            await increaseTime(stakeDuration);
            tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          });

          it("should update state", async function () {
            await tx;
            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            expect(aludelData.rewardSharesOutstanding).to.eq(0);
            expect(aludelData.totalStake).to.eq(0);
            expect(aludelData.totalStakeUnits).to.eq(0);
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());
            expect(vaultData.totalStake).to.eq(0);
            expect(vaultData.stakes.length).to.eq(0);
          });

          it("should emit event", async function () {
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, rewardToken.address, rewardAmount);
          });

          it("should transfer tokens", async function () {
            await expect(tx)
              .to.emit(rewardToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, rewardAmount);
          });

          it("should unlock tokens", async function () {
            await expect(tx)
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          });
        });

        describe("WHEN a user stays for a fifth of the fund duration", () => {
          const rewardAmount = subtractFundingFee(fundingAmount).div(5);
          const stakeDuration = defaultRewardScaling.time / 5;
          let tx: Promise<TransactionResponse>;
          let events: Array<LogDescription>;
          beforeEach(async () => {
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            await increaseTime(stakeDuration);
            tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            events = populateEvents(
              [aludel.interface, stakingToken.interface, vault.interface],
              (await (await tx).wait()).logs
            );
          });

          it("should update state", async function () {
            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            const expectedSharesBurnt = subtractFundingFee(fundingAmount)
              .mul(4)
              .div(5)
              .mul(BASE_SHARES_PER_WEI);
            // 1% margin for smol time elapsed by other things
            expect(aludelData.rewardSharesOutstanding).to.be.lt(
              expectedSharesBurnt
            );
            expect(aludelData.rewardSharesOutstanding).to.be.gt(
              expectedSharesBurnt.mul(99).div(100)
            );
            expect(aludelData.totalStake).to.eq(0);
            expect(aludelData.totalStakeUnits).to.eq(0);
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());
            expect(vaultData.totalStake).to.eq(0);
            expect(vaultData.stakes.length).to.eq(0);
          });

          it("should emit event", async function () {
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            // don't assert the value directly, since .withArgs doesn't support providing a range
            const rewardClaimedEvents = events.filter(
              (it) => it.name == "RewardClaimed"
            );
            expect(rewardClaimedEvents.length).to.eq(1);
            // 1% margin for smol time elapsed by other things
            expect(rewardClaimedEvents[0].args.vault).to.eq(vault.address);
            expect(rewardClaimedEvents[0].args.token).to.eq(
              rewardToken.address
            );
            expect(rewardClaimedEvents[0].args.amount).to.be.gt(rewardAmount);
            expect(rewardClaimedEvents[0].args.amount).to.be.lt(
              rewardAmount.mul(101).div(100)
            );
          });

          it("should transfer tokens", async function () {
            const transferEvents = events.filter(
              (it) => it.name === "Transfer"
            );
            expect(transferEvents.length).to.eq(1);
            expect(transferEvents[0].args.from).to.eq(rewardPool.address);
            expect(transferEvents[0].args.to).to.eq(vault.address);
            expect(transferEvents[0].args.amount).to.be.gt(rewardAmount);
            // 1% margin
            expect(transferEvents[0].args.amount).to.be.lt(
              rewardAmount.mul(101).div(100)
            );
          });

          it("should unlock tokens", async function () {
            await expect(tx)
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          });
        });
      });
      describe("with no reward", function () {
        let vault: Contract;
        beforeEach(async function () {
          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(0);
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with partially vested stake", function () {
        const expectedReward = calculateExpectedReward(
          stakeAmount,
          defaultRewardScaling.time,
          rewardAmount.div(2),
          0,
          defaultRewardScaling
        );

        let vault: Contract;
        beforeEach(async function () {
          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(defaultRewardScaling.time);

          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time / 2);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with flash stake", function () {
        let vault: Contract, MockStakeHelper: Contract;

        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          MockStakeHelper = await deployContract("MockStakeHelper");
        });
        it("should succeed", async function () {
          await MockStakeHelper.flashStake(
            aludel.address,
            vault.address,
            stakeAmount,
            await signPermission(
              "Lock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount
            ),
            await signPermission(
              "Unlock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount,
              (await vault.getNonce()).add(1)
            )
          );
        });
        it("should update state", async function () {
          await MockStakeHelper.flashStake(
            aludel.address,
            vault.address,
            stakeAmount,
            await signPermission(
              "Lock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount
            ),
            await signPermission(
              "Unlock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount,
              (await vault.getNonce()).add(1)
            )
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = MockStakeHelper.flashStake(
            aludel.address,
            vault.address,
            stakeAmount,
            await signPermission(
              "Lock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount
            ),
            await signPermission(
              "Unlock",
              vault,
              user,
              aludel.address,
              stakingToken.address,
              stakeAmount,
              (await vault.getNonce()).add(1)
            )
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
        });
        it("should lock tokens", async function () {
          await expect(
            MockStakeHelper.flashStake(
              aludel.address,
              vault.address,
              stakeAmount,
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                stakeAmount
              ),
              await signPermission(
                "Unlock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                stakeAmount,
                (await vault.getNonce()).add(1)
              )
            )
          )
            .to.emit(vault, "Locked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
        it("should unlock tokens", async function () {
          await expect(
            MockStakeHelper.flashStake(
              aludel.address,
              vault.address,
              stakeAmount,
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                stakeAmount
              ),
              await signPermission(
                "Unlock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                stakeAmount,
                (await vault.getNonce()).add(1)
              )
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with one second stake", function () {
        const stakeDuration = 2;
        const expectedReward = calculateExpectedReward(
          stakeAmount,
          stakeDuration,
          rewardAmount,
          0,
          defaultRewardScaling
        );

        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(stakeDuration);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount);
        });
      });
      describe("with partial amount from single stake", function () {
        const expectedReward = calculateExpectedReward(
          stakeAmount.div(2),
          defaultRewardScaling.time,
          rewardAmount,
          stakeAmount.div(2).mul(defaultRewardScaling.time),
          defaultRewardScaling
        );

        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);

          await stake(user, aludel, vault, stakingToken, stakeAmount);

          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount.div(2)]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount.div(2)]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(stakeAmount.div(2));
          expect(aludelData.totalStakeUnits).to.eq(
            stakeAmount.div(2).mul(defaultRewardScaling.time)
          );
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(stakeAmount.div(2));
          expect(vaultData.stakes.length).to.eq(1);
          expect(vaultData.stakes[0].amount).to.eq(stakeAmount.div(2));
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0],
            [stakeAmount.div(2)]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, stakeAmount.div(2));
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount.div(2)]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount.div(2)]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, stakeAmount.div(2));
        });
      });
      describe("with partial amount from multiple stakes", function () {
        const quantity = 3;
        // use 99 as stake amount to it would be divisible by 3
        const currentStake = ethers.utils.parseEther("99");
        // half of the total staked amount so it'll take an entire stake and a partial stake
        const unstakedAmount = currentStake.div(2);
        const expectedReward = calculateExpectedReward(
          unstakedAmount,
          defaultRewardScaling.time,
          rewardAmount,
          currentStake.div(2).mul(defaultRewardScaling.time),
          defaultRewardScaling
        ); // account for division dust

        let vault: Contract;
        // crafted so it has the same behaviour as it did before explicitly
        // telling it what to unstake
        const unstakes: [Array<number>, Array<BigNumberish>] = [
          [1, 2],
          [
            unstakedAmount.sub(currentStake.div(quantity)),
            currentStake.div(quantity),
          ],
        ];

        beforeEach(async function () {
          // fund aludel
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          // deploy vault and transfer stake
          vault = await createInstance("Crucible", vaultFactory, user);
          await stakingToken
            .connect(admin)
            .transfer(vault.address, currentStake);

          // perform multiple stakes in same block
          const permissions = [];
          for (let index = 0; index < quantity; index++) {
            permissions.push(
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                currentStake.div(quantity),
                index
              )
            );
          }
          const MockStakeHelper = await deployContract("MockStakeHelper");
          await MockStakeHelper.stakeBatch(
            new Array(quantity).fill(undefined).map(() => aludel.address),
            new Array(quantity).fill(undefined).map(() => vault.address),
            new Array(quantity)
              .fill(undefined)
              .map(() => currentStake.div(quantity)),
            permissions
          );

          // increase time to the end of reward scaling
          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(user, aludel, vault, stakingToken, ...unstakes);
        });
        it("should update state", async function () {
          await unstakeAndClaim(user, aludel, vault, stakingToken, ...unstakes);

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(currentStake.sub(unstakedAmount));
          expect(aludelData.totalStakeUnits).to.eq(
            currentStake.sub(unstakedAmount).mul(defaultRewardScaling.time)
          );
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(currentStake.sub(unstakedAmount));
          expect(vaultData.stakes.length).to.eq(2);
          // first stake should be untouched
          expect(vaultData.stakes[0].amount).to.eq(currentStake.div(3));
          // second stake should have half of its original amount
          expect(vaultData.stakes[1].amount).to.eq(currentStake.div(6));
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            ...unstakes
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, unstakedAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(user, aludel, vault, stakingToken, ...unstakes)
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(user, aludel, vault, stakingToken, ...unstakes)
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, unstakedAmount);
        });
      });
      describe("with full amount of the last of multiple stakes", function () {
        const currentStake = ethers.utils.parseEther("99");
        const unstakedAmount = currentStake.div(3);
        const expectedReward = calculateExpectedReward(
          unstakedAmount,
          defaultRewardScaling.time,
          rewardAmount,
          currentStake.sub(unstakedAmount).mul(defaultRewardScaling.time),
          defaultRewardScaling
        );

        const quantity = 3;

        let vault: Contract;
        beforeEach(async function () {
          // fund aludel
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          // deploy vault and transfer stake
          vault = await createInstance("Crucible", vaultFactory, user);
          await stakingToken
            .connect(admin)
            .transfer(vault.address, currentStake);

          // perform multiple stakes in same block
          const permissions = [];
          for (let index = 0; index < quantity; index++) {
            permissions.push(
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                currentStake.div(quantity),
                index
              )
            );
          }
          const MockStakeHelper = await deployContract("MockStakeHelper");
          await MockStakeHelper.stakeBatch(
            new Array(quantity).fill(aludel.address),
            new Array(quantity).fill(vault.address),
            new Array(quantity).fill(currentStake.div(quantity)),
            permissions
          );

          // increase time to the end of reward scaling
          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [2],
            [unstakedAmount]
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [2],
            [unstakedAmount]
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(currentStake.sub(unstakedAmount));
          expect(aludelData.totalStakeUnits).to.eq(
            currentStake.sub(unstakedAmount).mul(defaultRewardScaling.time)
          );
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(currentStake.sub(unstakedAmount));
          expect(vaultData.stakes.length).to.eq(2);
          expect(vaultData.stakes[0].amount).to.eq(currentStake.div(3));
          expect(vaultData.stakes[1].amount).to.eq(currentStake.div(3));
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [2],
            [unstakedAmount]
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, unstakedAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [2],
              [unstakedAmount]
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [2],
              [unstakedAmount]
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, unstakedAmount);
        });
      });
      describe("with full amount of multiple stakes", function () {
        const currentStake = ethers.utils.parseEther("99");
        const unstakedAmount = currentStake;
        const expectedReward = calculateExpectedReward(
          unstakedAmount,
          defaultRewardScaling.time,
          rewardAmount,
          0,
          defaultRewardScaling
        );
        const quantity = 3;

        let vault: Contract;
        beforeEach(async function () {
          // fund aludel
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          // deploy vault and transfer stake
          vault = await createInstance("Crucible", vaultFactory, user);
          await stakingToken
            .connect(admin)
            .transfer(vault.address, currentStake);

          // perform multiple stakes in same block
          const permissions = [];
          for (let index = 0; index < quantity; index++) {
            permissions.push(
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                currentStake.div(quantity),
                index
              )
            );
          }
          const MockStakeHelper = await deployContract("MockStakeHelper");
          await MockStakeHelper.stakeBatch(
            new Array(quantity).fill(aludel.address),
            new Array(quantity).fill(vault.address),
            new Array(quantity).fill(currentStake.div(quantity)),
            permissions
          );

          // increase time to the end of reward scaling
          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0, 1, 2],
            new Array(quantity).fill(currentStake.div(quantity))
          );
        });
        it("should update state", async function () {
          await unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0, 1, 2],
            new Array(quantity).fill(currentStake.div(quantity))
          );

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(0);
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
        it("should emit event", async function () {
          const tx = unstakeAndClaim(
            user,
            aludel,
            vault,
            stakingToken,
            [0, 1, 2],
            new Array(quantity).fill(currentStake.div(quantity))
          );
          await expect(tx)
            .to.emit(aludel, "Unstaked")
            .withArgs(vault.address, unstakedAmount);
          await expect(tx)
            .to.emit(aludel, "RewardClaimed")
            .withArgs(vault.address, rewardToken.address, expectedReward);
        });
        it("should transfer tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0, 1, 2],
              new Array(quantity).fill(currentStake.div(quantity))
            )
          )
            .to.emit(rewardToken, "Transfer")
            .withArgs(rewardPool.address, vault.address, expectedReward);
        });
        it("should unlock tokens", async function () {
          await expect(
            unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0, 1, 2],
              new Array(quantity).fill(currentStake.div(quantity))
            )
          )
            .to.emit(vault, "Unlocked")
            .withArgs(aludel.address, stakingToken.address, unstakedAmount);
        });
      });
      describe("when one bonus token", function () {
        let vault: Contract;
        beforeEach(async function () {
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          await aludel.connect(admin).registerBonusToken(bonusToken.address);

          vault = await createInstance("Crucible", vaultFactory, user);

          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);
        });
        describe("with no bonus token balance", function () {
          beforeEach(async function () {
            await stake(user, aludel, vault, stakingToken, stakeAmount);
            await increaseTime(defaultRewardScaling.time);
          });
          it("should succeed", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          });
          it("should update state", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );

            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            expect(aludelData.rewardSharesOutstanding).to.eq(0);
            expect(aludelData.totalStake).to.eq(0);
            expect(aludelData.totalStakeUnits).to.eq(0);
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());
            expect(vaultData.totalStake).to.eq(0);
            expect(vaultData.stakes.length).to.eq(0);
          });
          it("should emit event", async function () {
            const tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, rewardToken.address, rewardAmount);
          });
          it("should transfer tokens", async function () {
            const txPromise = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(txPromise)
              .to.emit(rewardToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, rewardAmount);
          });
          it("should unlock tokens", async function () {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            )
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          });
        });
        describe("with fully vested stake", function () {
          beforeEach(async function () {
            await bonusToken
              .connect(admin)
              .transfer(rewardPool.address, mockTokenSupply);

            await stake(user, aludel, vault, stakingToken, stakeAmount);

            await increaseTime(defaultRewardScaling.time);
          });
          it("should succeed", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          });
          it("should update state", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );

            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            expect(aludelData.rewardSharesOutstanding).to.eq(0);
            expect(aludelData.totalStake).to.eq(0);
            expect(aludelData.totalStakeUnits).to.eq(0);
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());
            expect(vaultData.totalStake).to.eq(0);
            expect(vaultData.stakes.length).to.eq(0);
          });
          it("should emit event", async function () {
            const tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, rewardToken.address, rewardAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, bonusToken.address, mockTokenSupply);
          });
          it("should transfer tokens", async function () {
            const txPromise = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(txPromise)
              .to.emit(rewardToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, rewardAmount);
            await expect(txPromise)
              .to.emit(bonusToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, mockTokenSupply);
          });
          it("should unlock tokens", async function () {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            )
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          });
        });
        describe("with partially vested stake", function () {
          const stakeDuration = defaultRewardScaling.time / 2;
          const expectedReward = calculateExpectedReward(
            stakeAmount,
            stakeDuration,
            rewardAmount,
            0,
            defaultRewardScaling
          );
          const expectedBonus = calculateExpectedReward(
            stakeAmount,
            stakeDuration,
            mockTokenSupply,
            0,
            defaultRewardScaling
          );
          beforeEach(async function () {
            await bonusToken
              .connect(admin)
              .transfer(rewardPool.address, mockTokenSupply);

            await stake(user, aludel, vault, stakingToken, stakeAmount);

            await increaseTime(stakeDuration);
          });
          it("should succeed", async function () {
            await unstakeAndClaim(
              user,

              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          });
          it("should update state", async function () {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );

            const aludelData = await aludel.getAludelData();
            const vaultData = await aludel.getVaultData(vault.address);

            expect(aludelData.rewardSharesOutstanding).to.eq(
              rewardAmount.sub(expectedReward).mul(BASE_SHARES_PER_WEI)
            );
            expect(aludelData.totalStake).to.eq(0);
            expect(aludelData.totalStakeUnits).to.eq(0);
            expect(aludelData.lastUpdate).to.eq(await getTimestamp());
            expect(vaultData.totalStake).to.eq(0);
            expect(vaultData.stakes.length).to.eq(0);
          });
          it("should emit event", async function () {
            const tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, rewardToken.address, expectedReward);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(vault.address, bonusToken.address, expectedBonus);
          });
          it("should transfer tokens", async function () {
            const txPromise = unstakeAndClaim(
              user,

              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(txPromise)
              .to.emit(rewardToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, expectedReward);
            await expect(txPromise)
              .to.emit(bonusToken, "Transfer")
              .withArgs(rewardPool.address, vault.address, expectedBonus);
          });
          it("should unlock tokens", async function () {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            )
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          });
        });
      });
      describe("with multiple vaults", function () {
        const stakeAmount = ethers.utils.parseEther("1");

        const rewardAmount = subtractFundingFee(fundingAmount);
        const quantity = 10;

        let vaults: Array<Contract>;
        beforeEach(async function () {
          // fund aludel
          await rewardToken
            .connect(admin)
            .approve(aludel.address, fundingAmount);
          await aludel
            .connect(admin)
            .fund(fundingAmount, defaultRewardScaling.time);

          await increaseTime(defaultRewardScaling.time);

          // create vaults
          vaults = [];
          const permissions = [];
          for (let index = 0; index < quantity; index++) {
            const vault = await createInstance("Crucible", vaultFactory, user);
            await stakingToken
              .connect(admin)
              .transfer(vault.address, stakeAmount);

            vaults.push(vault);

            permissions.push(
              await signPermission(
                "Lock",
                vault,
                user,
                aludel.address,
                stakingToken.address,
                stakeAmount
              )
            );
          }

          // stake in same block
          const MockStakeHelper = await deployContract("MockStakeHelper");
          await MockStakeHelper.stakeBatch(
            new Array(quantity).fill(aludel.address),
            vaults.map((vault) => vault.address),
            new Array(quantity).fill(stakeAmount),
            permissions
          );

          // increase time to end of reward scaling
          await increaseTime(defaultRewardScaling.time);
        });
        it("should succeed", async function () {
          for (const vault of vaults) {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          }
        });
        it("should update state", async function () {
          for (const vault of vaults) {
            await unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
          }

          const aludelData = await aludel.getAludelData();

          expect(aludelData.rewardSharesOutstanding).to.eq(0);
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
        });
        it("should emit event", async function () {
          for (const vault of vaults) {
            const tx = unstakeAndClaim(
              user,
              aludel,
              vault,
              stakingToken,
              [0],
              [stakeAmount]
            );
            await expect(tx)
              .to.emit(aludel, "Unstaked")
              .withArgs(vault.address, stakeAmount);
            await expect(tx)
              .to.emit(aludel, "RewardClaimed")
              .withArgs(
                vault.address,
                rewardToken.address,
                rewardAmount.div(quantity)
              );
          }
        });
        it("should transfer tokens", async function () {
          for (const vault of vaults) {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            )
              .to.emit(rewardToken, "Transfer")
              .withArgs(
                rewardPool.address,
                vault.address,
                rewardAmount.div(quantity)
              );
          }
        });
        it("should unlock tokens", async function () {
          for (const vault of vaults) {
            await expect(
              unstakeAndClaim(
                user,
                aludel,
                vault,
                stakingToken,
                [0],
                [stakeAmount]
              )
            )
              .to.emit(vault, "Unlocked")
              .withArgs(aludel.address, stakingToken.address, stakeAmount);
          }
        });
      });
    });

    describe("rageQuit", function () {
      const stakeAmount = ethers.utils.parseEther("100");
      const fundingAmount = ethers.utils.parseUnits("1000", 9);
      const rewardAmount = subtractFundingFee(fundingAmount);
      const gasLimit = 600_000;

      let vault: Contract;
      beforeEach(async function () {
        // fund aludel
        await rewardToken.connect(admin).approve(aludel.address, fundingAmount);
        await aludel
          .connect(admin)
          .fund(fundingAmount, defaultRewardScaling.time);

        // create vault
        vault = await createInstance("Crucible", vaultFactory, user);

        // stake
        await stakingToken.connect(admin).transfer(vault.address, stakeAmount);
        await stake(user, aludel, vault, stakingToken, stakeAmount);
      });
      describe("when online", function () {
        it("should succeed", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });
        });
        it("should update state", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
      });
      describe("when offline", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).powerOff();
        });
        it("should succeed", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });
        });
        it("should update state", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
      });
      describe("when shutdown", function () {
        beforeEach(async function () {
          await powerSwitch.connect(admin).emergencyShutdown();
        });
        it("should succeed", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });
        });
        it("should update state", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
      });
      describe("with unknown vault", function () {
        it("should fail", async function () {
          await expect(
            aludel.connect(user).rageQuit({
              gasLimit,
            })
          ).to.be.revertedWithCustomError(aludel, "NoStakes");
        });
      });
      describe("when no stake", function () {
        it("should fail", async function () {
          const secondVault = await createInstance(
            "Crucible",
            vaultFactory,
            user
          );
          await expect(
            secondVault
              .connect(user)
              .rageQuit(aludel.address, stakingToken.address, {
                gasLimit,
              })
          ).to.be.revertedWith("UniversalVault: missing lock");
        });
      });
      describe("when insufficient gas", function () {
        it("should fail", async function () {
          await expect(
            vault.connect(user).rageQuit(aludel.address, stakingToken.address, {
              gasLimit: await vault.RAGEQUIT_GAS(),
            })
          ).to.be.revertedWith("UniversalVault: insufficient gas");
        });
      });
      describe("when insufficient gas with multiple stakes", function () {
        let quantity: number;
        beforeEach(async function () {
          quantity = (await aludel.MAX_STAKES_PER_VAULT()).toNumber() - 1;
          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);
          for (let index = 0; index < quantity; index++) {
            await stake(
              user,
              aludel,
              vault,
              stakingToken,
              stakeAmount.div(quantity)
            );
          }
        });
        it("should fail", async function () {
          await expect(
            vault.connect(user).rageQuit(aludel.address, stakingToken.address, {
              gasLimit: await vault.RAGEQUIT_GAS(),
            })
          ).to.be.revertedWith("UniversalVault: insufficient gas");
        });
      });
      describe("when single stake", function () {
        it("should succeed", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });
        });
        it("should update state", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
      });
      describe("when multiple stakes", function () {
        let quantity: number;

        beforeEach(async function () {
          quantity = (await aludel.MAX_STAKES_PER_VAULT()).toNumber() - 1;
          await stakingToken
            .connect(admin)
            .transfer(vault.address, stakeAmount);
          for (let index = 0; index < quantity; index++) {
            await stake(
              user,
              aludel,
              vault,
              stakingToken,
              stakeAmount.div(quantity)
            );
          }
        });
        it("should succeed", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });
        });
        it("should update state", async function () {
          await vault
            .connect(user)
            .rageQuit(aludel.address, stakingToken.address, {
              gasLimit,
            });

          const aludelData = await aludel.getAludelData();
          const vaultData = await aludel.getVaultData(vault.address);

          expect(aludelData.rewardSharesOutstanding).to.eq(
            rewardAmount.mul(BASE_SHARES_PER_WEI)
          );
          expect(aludelData.totalStake).to.eq(0);
          expect(aludelData.totalStakeUnits).to.eq(0);
          expect(aludelData.lastUpdate).to.eq(await getTimestamp());
          expect(vaultData.totalStake).to.eq(0);
          expect(vaultData.stakes.length).to.eq(0);
        });
      });
    });
  });
});
