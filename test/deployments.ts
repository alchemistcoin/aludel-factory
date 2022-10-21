import { expect } from "chai";
import { AbiCoder } from "ethers/lib/utils";
import { deployments, ethers } from "hardhat";
import {
  AludelFactory,
  CrucibleFactory,
  MockERC20,
  PowerSwitchFactory,
  RewardPoolFactory,
} from "../typechain-types";
import { DAYS } from "./utils";

describe("Aludel factory deployments", function () {
  describe("WHEN deploying a template set", () => {
    let factory: AludelFactory;
    beforeEach(async () => {
      await deployments.fixture(["templates"], {
        keepExistingDeployments: true,
      });
      const deployedFactory = await deployments.get("AludelFactory");
      factory = (await ethers.getContractAt(
        deployedFactory.abi,
        deployedFactory.address
      )) as AludelFactory;
    });
    it("THEN GeyserV2 and AludelV1 reserved template addresses are added in a disabled state", async () => {
      const geyserv2 = await factory.getTemplate(
        "0x00000000000000000000000000000000be15efb2"
      );
      expect(geyserv2.disabled).to.be.true;
      expect(geyserv2.name).to.be.equal("GeyserV2");
      const aludelv1 = await factory.getTemplate(
        "0x00000000000000000000000000000000a1fde1b1"
      );
      expect(aludelv1.disabled).to.be.true;
      expect(aludelv1.name).to.be.equal("AludelV1");
    });
    it("AND an Aludel is added as an enabled template", async () => {
      const aludelDeployment = await deployments.get("AludelV2");
      const aludelTemplate = await factory.getTemplate(
        aludelDeployment.address
      );
      expect(aludelTemplate.disabled).to.be.false;
      expect(aludelTemplate.name).to.be.equal("AludelV2");
    });

    async function deployMockERC20(name: string): Promise<MockERC20> {
      const factory = await ethers.getContractFactory("MockERC20");
      return (await factory.deploy(name, "MockERC20")) as MockERC20;
    }

    describe("GIVEN a PowerSwitchFactory, a CrucibleFactory, a RewardPoolFactory, and some other stuff", () => {
      let powerSwitchFactory: PowerSwitchFactory;
      let crucibleFactory: CrucibleFactory;
      let rewardPoolFactory: RewardPoolFactory;
      let stakingToken: MockERC20;
      let rewardToken: MockERC20;
      beforeEach(async () => {
        await deployments.fixture(
          ["PowerSwitchFactory", "CrucibleFactory", "RewardPoolFactory"],
          { keepExistingDeployments: true }
        );
        const powerSwitchDeployment = await deployments.get(
          "PowerSwitchFactory"
        );
        powerSwitchFactory = (await ethers.getContractAt(
          powerSwitchDeployment.abi,
          powerSwitchDeployment.address
        )) as PowerSwitchFactory;
        const crucibleFactoryDeployment = await deployments.get(
          "CrucibleFactory"
        );
        crucibleFactory = (await ethers.getContractAt(
          crucibleFactoryDeployment.abi,
          crucibleFactoryDeployment.address
        )) as CrucibleFactory;
        const rewardPoolFactoryDeployment = await deployments.get(
          "RewardPoolFactory"
        );
        rewardPoolFactory = (await ethers.getContractAt(
          rewardPoolFactoryDeployment.abi,
          rewardPoolFactoryDeployment.address
        )) as RewardPoolFactory;
        [stakingToken, rewardToken] = await Promise.all([
          deployMockERC20("STAKE"),
          deployMockERC20("REWARD"),
        ]);
      });

      describe("AND GIVEN a valid template address and deploy params", async () => {
        let templateAddress: string;
        let deployParams: string;

        beforeEach(async () => {
          const aludelTemplateDeployment = await deployments.get("AludelV2");
          templateAddress = aludelTemplateDeployment.address;

          deployParams = new AbiCoder().encode(
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
          );
        });
        it("THEN an aludel can be launched manually", async () => {
          const tx = await factory.launch(
            templateAddress,
            "program name",
            "protocol://program.url",
            0,
            crucibleFactory.address,
            [],
            await factory.owner(),
            deployParams
          );
          await tx.wait();
        });
      });
    });
  });
});
