import { AbiCoder } from "@ethersproject/abi"
import { parseEther } from "@ethersproject/units"
import { Wallet } from "@ethersproject/wallet"
import { Event } from "@ethersproject/contracts"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { expect } from "chai"
import { Contract } from "ethers"
import {
  deployments as hardhatDeployments,
  network,
  ethers as hardhatEthers,
} from "hardhat"
import { DeployedContract } from "hardhat-deploy/dist/types"
import {
  Aludel,
  AludelFactory,
  Crucible,
  CrucibleFactory,
  MockERC20,
  RewardPoolFactory,
} from "../typechain-types"
import { DAYS, ETHER, signPermission } from "./utils"
import { AddressZero } from "@ethersproject/constants"

describe("Aludel factory", function () {
  const setupTest = hardhatDeployments.createFixture(
    async ({ deployments, ethers }) => {
      await deployments.fixture(undefined, {
        keepExistingDeployments: true,
      })
      const signers = await ethers.getSigners()
      const [admin, user, anotherUser] = signers

      const stakingToken: MockERC20 = await deployMockERC20("StakingToken")
      const rewardToken: MockERC20 = await deployMockERC20("RewardToken")
      const bonusTokenA: MockERC20 = await deployMockERC20("BonusTokenA")
      const bonusTokenB: MockERC20 = await deployMockERC20("BonusTokenB")

      const factoryDeployment = await deployments.get("AludelFactory")
      const factory: AludelFactory = (await ethers.getContractAt(
        factoryDeployment.abi,
        factoryDeployment.address
      )) as AludelFactory
      const crucibleFactory = await deployments.get("CrucibleFactory")
      const rewardPoolFactory = await deployments.get("RewardPoolFactory")
      const powerSwitchFactory = await deployments.get("PowerSwitchFactory")

      const deployedAludel = await deployments.get("Aludel")
      const aludelTemplate = (await ethers.getContractAt(
        "src/contracts/aludel/Aludel.sol:Aludel",
        deployedAludel.address,
        admin
      )) as Aludel

      await rewardToken.mint(admin.address, ETHER(1))
      const params = new AbiCoder().encode(
        [
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
          1,
          10,
          DAYS(1),
        ]
      )
      const startTime = 0
      const launchTx = await factory.launch(
        aludelTemplate.address,
        "program test",
        "https://staking.token",
        startTime,
        crucibleFactory.address,
        [bonusTokenA.address, bonusTokenB.address],
        admin.address,
        params
      )
      const receipt = await launchTx.wait()

      const event = receipt.events?.find(
        (it: Event) =>
          it.address == factory.address && it.event == "ProgramAdded"
      )
      const aludelAddress = event?.args!.program
      const aludel = aludelTemplate.attach(aludelAddress) as Aludel

      await rewardToken.connect(admin).approve(aludel.address, ETHER(1))

      await aludel.connect(admin).fund(ETHER(1), DAYS(1))
      return {
        crucibleFactory: await ethers.getContractAt(
          crucibleFactory.abi,
          crucibleFactory.address
        ),
        factory,
        powerSwitchFactory: await ethers.getContractAt(
          powerSwitchFactory.abi,
          powerSwitchFactory.address
        ),
        rewardPoolFactory: await ethers.getContractAt(
          rewardPoolFactory.abi,
          rewardPoolFactory.address
        ),
        aludel,
        aludelTemplate,
        bonusTokenB,
        bonusTokenA,
        stakingToken,
        rewardToken,
        admin,
        user,
        anotherUser,
      }
    }
  )

  async function deployMockERC20(name: string): Promise<MockERC20> {
    const factory = await hardhatEthers.getContractFactory("MockERC20")
    return (await factory.deploy(name, "MockERC20")) as MockERC20
  }

  describe("aludel launch", async function () {
    it("test full", async function () {
      const { crucibleFactory, aludel, admin, stakingToken } =
        await setupTest()
      let receipt = await (
        await crucibleFactory.connect(admin)["create()"]()
      ).wait()
      let event = receipt.events?.find(
        (it: Event) =>
          it.address == crucibleFactory.address && it.event == "InstanceAdded"
      )
      const crucibleAddress = event?.args!.instance

      const crucible = (await hardhatEthers.getContractAt(
        "Crucible",
        crucibleAddress
      )) as Crucible

      await stakingToken.connect(admin).mint(crucible.address, ETHER(1))

      const signerWallet = Wallet.fromMnemonic(process.env.DEV_MNEMONIC || "")
      let tx = await aludel.stake(
        crucible.address,
        ETHER(1),
        await signPermission(
          "Lock",
          crucible,
          signerWallet,
          aludel.address,
          stakingToken.address,
          ETHER(1),
          0
        )
      )
      await tx.wait()

      await network.provider.send("evm_increaseTime", [DAYS(1)])

      await aludel.unstakeAndClaim(
        crucible.address,
        ETHER(1),
        await signPermission(
          "Unlock",
          crucible,
          signerWallet,
          aludel.address,
          stakingToken.address,
          ETHER(1),
          1
        )
      )
    })

    describe("admin functions", async function () {
      it("templates", async function () {
        const { factory } = await setupTest()
        const templateFactory = await hardhatEthers.getContractFactory(
          "src/contracts/aludel/Aludel.sol:Aludel"
        )
        const template2 = (await templateFactory.deploy()) as Aludel
        await factory.addTemplate(template2.address, "aludel 2", false)
        let templateData = await factory.getTemplate(template2.address)
        expect(templateData.disabled).to.be.false
        expect(templateData.name).equals("aludel 2")
        await factory.updateTemplate(template2.address, true)
        templateData = await factory.getTemplate(template2.address)
        expect(templateData.disabled).to.be.true
      })

      it("programs", async function () {
        const { factory, aludel } = await setupTest()
        let program = await factory.programs(aludel.address)
        expect(program.name, "program test")
        expect(program.stakingTokenUrl, "https://staking.token")
        expect(
          program.stakingTokenUrl,
          (await factory.programs(aludel.address)).stakingTokenUrl
        )
        await factory.updateProgram(
          aludel.address,
          "changed",
          "https://invalid.url"
        )
        program = await factory.programs(aludel.address)
        expect(program.name, "changed")
        expect(program.stakingTokenUrl, "https://invalid.url")
        expect(
          program.stakingTokenUrl,
          (await factory.programs(aludel.address)).stakingTokenUrl
        )
      })

      it("add program", async function () {
        const { factory } = await setupTest()
        const templateFactory = await hardhatEthers.getContractFactory(
          "src/contracts/aludel/Aludel.sol:Aludel"
        )
        const template2 = (await templateFactory.deploy()) as Aludel
        await factory.addProgram(
          AddressZero,
          template2.address,
          "program added manually",
          "https://new.url",
          0
        )
        let program = await factory.programs(AddressZero)
        expect(program.name, "program added manually")
        expect(program.stakingTokenUrl, "https://new.url")
      })

      it("delist program", async function () {
        const { factory, aludel, aludelTemplate } = await setupTest()
        await factory.delistProgram(aludel.address)
        await factory.addProgram(
          aludel.address,
          aludelTemplate.address,
          "program added manually",
          "https://new.url",
          0
        )
        let program = await factory.programs(aludel.address)
        expect(program.name, "program added manually")
        expect(program.stakingTokenUrl, "https://new.url")
      })

      it("funding fee", async function () {
        const { factory, admin } = await setupTest()
        let bps = await factory.feeBps()
        let receiver = await factory.feeRecipient()
        expect(bps).eq(100)
        expect(receiver).equals(admin.address)
        await factory.setFeeBps(200)
        await factory.setFeeRecipient(AddressZero)
        bps = await factory.feeBps()
        receiver = await factory.feeRecipient()
        expect(bps).eq(200)
        expect(receiver).equals(AddressZero)
      })
    })
  })
})
